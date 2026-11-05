import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum ServerState: Equatable {
    case stopped
    case running(port: Int)
    case failed(message: String)
}

enum SidebarItem: Hashable {
    case allFlows
    case device(String)
    case host(String)
}

@MainActor @Observable
final class AppModel {
    static let supportDirectory = URL.applicationSupportDirectory.appending(path: "com.tv.eyeproxy")
    static let caDirectory = supportDirectory.appending(path: "ca")

    let settings = AppSettings()
    let session = SessionStore()
    let devices: DeviceRegistry
    let certificateAuthority: CertificateAuthority
    /// 새로 만든 CA를 저장하지 못했으면 그 이유. 매 실행 새 루트 CA가 되므로 Task 15 인증서 화면에서 표시한다.
    let caSaveError: String?
    private(set) var serverState: ServerState = .stopped
    var filter = FlowFilter()
    var selectedFlowID: FlowID?
    var sidebarSelection: SidebarItem? = .allFlows

    // 온보딩(기기 윈도우)
    @ObservationIgnored let systemProxy = SystemProxy(backupURL: supportDirectory.appending(path: "system-proxy-backup.json"))
    private(set) var macCaptureEnabled = false
    private(set) var macCaptureBusy = false
    private(set) var macCAInstalled = false
    private(set) var bootedSimulators: [SimulatorDevice] = []
    /// 시작 시 남아 있던 시스템 프록시 백업(비정상 종료). nil로 만들면 alert가 닫힌다.
    var pendingProxyRestore: SystemProxyBackup?
    /// 시스템 프록시·CA 설치·프로필 저장 실패. 키 윈도우에 alert로 표시한다.
    var systemError: String?

    @ObservationIgnored private var server: ProxyServer?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private var settingsUpdate: Task<Void, Never>?

    init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        devices = DeviceRegistry(storageURL: Self.supportDirectory.appending(path: "devices.json"))
        (certificateAuthority, caSaveError) = Self.loadOrCreateCA()
        // 이 실행은 아직 캡처를 켜지 않았으므로 백업이 있으면 이전 실행이 복원하지 못한 것이다.
        pendingProxyRestore = systemProxy.pendingRestore()
    }

    /// 손상(한쪽 파일만 있음·읽기 실패)이면 기존 파일을 덮어쓰지 않고 이번 실행만 임시 CA를 쓴다.
    /// 저장 실패(caSaveError)는 기기 윈도우에 표시한다. ponytail: 손상으로 임시 CA를 쓰는 경우는 아직 UI에 알리지 않음.
    private static func loadOrCreateCA() -> (CertificateAuthority, String?) {
        do {
            if let ca = try CertificateAuthority.load(from: caDirectory) { return (ca, nil) }
            let ca = try CertificateAuthority.generate()
            do {
                try ca.save(to: caDirectory)
                return (ca, nil)
            } catch {
                return (ca, error.localizedDescription)
            }
        } catch {
            guard let ca = try? CertificateAuthority.generate() else { fatalError("CA 생성 실패: \(error)") }
            return (ca, nil)
        }
    }

    // MARK: - 서버

    func startServer() async {
        guard server == nil else { return }
        let server = ProxyServer(
            configuration: .init(port: settings.port, sslPolicy: settings.sslPolicy),
            certificateAuthority: certificateAuthority,
            interceptors: .init(request: [CAProfileResponder(certificateAuthority: certificateAuthority)]))
        self.server = server
        // events는 단일 소비자이고 끝나지 않는다 → stopServer에서 취소한다.
        consumer = Task { [weak self] in
            for await event in server.events { self?.handle(event) }
        }
        do {
            let port = try await server.start()
            guard self.server === server else { return }   // 기다리는 동안 stopServer가 불렸다
            serverState = .running(port: port)
        } catch {
            guard self.server === server else { return }
            if case ProxyServerError.portInUse(let p) = error {
                serverState = .failed(message: String(localized: "포트 \(String(p)) 사용 중 — Proxyman을 끄거나 설정에서 포트를 바꾸세요"))
            } else {
                serverState = .failed(message: error.localizedDescription)
            }
            consumer?.cancel()
            consumer = nil
            self.server = nil
        }
    }

    func stopServer() async {
        consumer?.cancel()
        consumer = nil
        let running = server
        server = nil
        serverState = .stopped
        await running?.stop()
    }

    /// 호출 순서대로 직렬화한다. 각 갱신은 실행 시점의 설정을 읽으므로 마지막 토글이 이긴다.
    func applySettingsToServer() async {
        let previous = settingsUpdate
        let update = Task {
            await previous?.value
            await server?.update(sslPolicy: settings.sslPolicy)
        }
        settingsUpdate = update
        await update.value
    }

    private func handle(_ event: FlowEvent) {
        let isNewFlow = if case .requestStarted = event { true } else { false }
        // 기록 중지 상태에서도 이미 보이는 요청의 응답·실패는 반영한다.
        if settings.isRecording || !isNewFlow { session.apply(event) }
        devices.observe(event)
    }

    // MARK: - 동작

    func enableSSLProxying(for host: String) async {
        if !settings.sslPatterns.contains(host) { settings.sslPatterns.append(host) }
        settings.sslEnabled = true
        await applySettingsToServer()
    }

    func clear() {
        session.clear()
        selectedFlowID = nil
        // 지우면 도메인 목록이 비어 선택된 호스트 행이 사라진다 → 보이지 않는 필터가 남지 않게.
        if case .host = sidebarSelection { sidebarSelection = .allFlows }
    }

    // MARK: - 목록

    var visibleFlows: [Flow] {
        var f = filter
        switch sidebarSelection {
        case .device(let address): f.device = address
        case .host(let host): f.host = host
        case .allFlows, nil: break
        }
        return session.flows.filter(f.matches)
    }

    var hosts: [(host: String, count: Int)] {
        session.flows.reduce(into: [String: Int]()) { $0[$1.request.host, default: 0] += 1 }
            .map { (host: $0.key, count: $0.value) }
            .sorted { $0.host < $1.host }
    }

    // MARK: - 온보딩

    func setMacCapture(_ on: Bool) async {
        guard !macCaptureBusy, on != macCaptureEnabled else { return }
        macCaptureBusy = true
        defer { macCaptureBusy = false }
        do {
            if on {
                try await systemProxy.enable(host: "127.0.0.1", port: settings.port, bypass: settings.bypassHosts)
            } else {
                try await systemProxy.disable()
            }
            macCaptureEnabled = on
        } catch {
            systemError = on ? String(localized: "시스템 프록시를 켜지 못했습니다: \(String(describing: error))")
                             : String(localized: "시스템 프록시를 되돌리지 못했습니다: \(String(describing: error))")
        }
    }

    func restorePendingProxy() async {
        pendingProxyRestore = nil
        do { try await systemProxy.disable() } catch {
            systemError = String(localized: "시스템 프록시를 되돌리지 못했습니다: \(String(describing: error))")
        }
    }

    /// 실행 중인 CA의 PEM. 디스크 CA와 다를 수 있으므로(손상 시 임시 CA) 메모리 CA를 임시 파일로 쓴다.
    private func caPEMFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "eyeproxy-ca.pem")
        try Data(certificateAuthority.certificatePEM.utf8).write(to: url, options: .atomic)
        return url
    }

    func refreshMacCAInstalled() async {
        guard let pem = try? caPEMFile() else { macCAInstalled = false; return }
        macCAInstalled = await MacKeychain.isInstalled(pemURL: pem)
    }

    func installCAOnMac() async throws {
        try await MacKeychain.installTrustedRoot(pemURL: caPEMFile())
        await refreshMacCAInstalled()
    }

    /// 실패(Xcode 없음 등)는 빈 목록으로 보인다.
    func refreshSimulators() async {
        bootedSimulators = ((try? await Simulators.listBooted()) ?? []).sorted { ($0.runtime, $0.name) < ($1.runtime, $1.name) }
    }

    func installCA(toSimulator udid: String) async throws {
        try await Simulators.installRootCert(udid: udid, pemURL: caPEMFile())
    }

    /// 평문 비밀번호 경고는 호출 전에 뷰가 띄운다. 비밀번호는 파일에만 들어가고 앱은 보관하지 않는다.
    func saveWiFiProfile(ssid: String, security: WiFiSecurity, password: String?, proxyHost: String) async {
        let panel = NSSavePanel()
        let safeName = ssid.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "EyeProxy-\(safeName).mobileconfig"
        panel.allowedContentTypes = [.init(filenameExtension: "mobileconfig") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = MobileConfig.wifiProxyProfile(ssid: ssid, security: security, password: security == .none ? nil : password,
                                                 proxyHost: proxyHost, proxyPort: settings.port)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            systemError = String(localized: "프로필을 저장하지 못했습니다: \(error.localizedDescription)")
        }
    }
}
