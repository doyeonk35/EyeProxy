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
    /// 디스크에 원본 백업이 있다 = 시스템 프록시가 EyeProxy를 가리키고 있다(캡처 중이거나 복원 전).
    private(set) var systemProxyBackupExists = false
    /// 시스템 프록시·CA 설치·프로필 저장 실패. 키 윈도우에 alert로 표시한다.
    var systemError: String?

    @ObservationIgnored private var server: ProxyServer?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private var settingsUpdate: Task<Void, Never>?
    @ObservationIgnored private var captureUpdate: Task<Void, Never>?

    init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        devices = DeviceRegistry(storageURL: Self.supportDirectory.appending(path: "devices.json"))
        (certificateAuthority, caSaveError) = Self.loadOrCreateCA()
        // 이 실행은 아직 캡처를 켜지 않았으므로 백업이 있으면 이전 실행이 복원하지 못한 것이다.
        pendingProxyRestore = systemProxy.pendingRestore()
        systemProxyBackupExists = pendingProxyRestore != nil
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

    /// 호출 순서대로 직렬화한다(종료 경로가 진행 중인 켜기·끄기를 기다릴 수 있게).
    func setMacCapture(_ on: Bool) async {
        let previous = captureUpdate
        let update = Task {
            await previous?.value
            await applyMacCapture(on)
        }
        captureUpdate = update
        await update.value
    }

    private func applyMacCapture(_ on: Bool) async {
        // 끄기는 캡처 중이 아니어도 백업이 남아 있으면 복원한다(유지 후 실패·비정상 종료 잔여).
        let needed = on ? !macCaptureEnabled : (macCaptureEnabled || systemProxy.pendingRestore() != nil)
        guard needed else { return }
        macCaptureBusy = true
        defer {
            macCaptureBusy = false
            systemProxyBackupExists = systemProxy.pendingRestore() != nil
        }
        do {
            if on {
                try await systemProxy.enable(host: "127.0.0.1", port: settings.port, bypass: settings.bypassHosts)
            } else {
                try await systemProxy.disable()
            }
            macCaptureEnabled = on
        } catch {
            // 켜기 실패(관리자 인증 취소 등): 일부만 적용됐을 수 있으니 백업으로 되돌린다. 백업 없으면 원본을 모르므로 건드리지 않는다.
            if on, systemProxy.pendingRestore() != nil { try? await systemProxy.disable() }
            systemError = on ? String(localized: "시스템 프록시를 켜지 못했습니다: \(Self.describe(error))")
                             : String(localized: "시스템 프록시를 되돌리지 못했습니다: \(Self.describe(error))")
        }
    }

    /// 종료 전에 시스템 프록시를 되돌려야 하는가(캡처 중·변경 중·백업 잔여).
    var needsProxyCleanupOnQuit: Bool {
        macCaptureEnabled || macCaptureBusy || systemProxy.pendingRestore() != nil
    }

    func prepareForQuit() async {
        await setMacCapture(false)   // 진행 중인 변경 뒤에 직렬화된다
        await stopServer()
    }

    func restorePendingProxy() async {
        pendingProxyRestore = nil
        await setMacCapture(false)
    }

    /// "유지": 남은 프록시를 이번 실행의 캡처로 채택한다. 원본 백업은 그대로 두고 현재 포트로 다시 맞춘다.
    func adoptPendingProxy() async {
        pendingProxyRestore = nil
        await setMacCapture(true)
    }

    /// 사용자에게 보일 오류 문구. 관리자 인증 취소(osascript -128)는 따로 알린다.
    static func describe(_ error: Error) -> String {
        let text = switch error {
        case SystemProxyError.commandFailed(let s), MacKeychainError.installFailed(let s), SimulatorsError.failed(let s): s
        case SystemProxyError.noActiveService: String(localized: "활성 네트워크 서비스를 찾지 못했습니다")
        default: error.localizedDescription
        }
        if text.contains("-128") || text.localizedCaseInsensitiveContains("canceled") || text.localizedCaseInsensitiveContains("cancelled") {
            return String(localized: "관리자 인증이 취소되었습니다")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// 저장했으면 true.
    @discardableResult
    func saveWiFiProfile(ssid: String, security: WiFiSecurity, password: String?, proxyHost: String) async -> Bool {
        let panel = NSSavePanel()
        let safeName = ssid.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "EyeProxy-\(safeName).mobileconfig"
        panel.allowedContentTypes = [.init(filenameExtension: "mobileconfig") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let data = MobileConfig.wifiProxyProfile(ssid: ssid, security: security, password: security == .none ? nil : password,
                                                 proxyHost: proxyHost, proxyPort: settings.port)
        // 비밀번호가 평문으로 들어가므로 처음부터 0600으로 만든다(덮어쓰기면 기존 파일을 지우고 새로 만든다).
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            systemError = String(localized: "프로필을 저장하지 못했습니다: \(url.path)")
            return false
        }
        return true
    }
}
