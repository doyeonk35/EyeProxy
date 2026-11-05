import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import Observation

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
    private(set) var serverState: ServerState = .stopped
    var filter = FlowFilter()
    var selectedFlowID: FlowID?
    var sidebarSelection: SidebarItem? = .allFlows

    @ObservationIgnored private var server: ProxyServer?
    @ObservationIgnored private var consumer: Task<Void, Never>?

    init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        devices = DeviceRegistry(storageURL: Self.supportDirectory.appending(path: "devices.json"))
        certificateAuthority = Self.loadOrCreateCA()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            // 리슨 소켓은 프로세스 종료 시 커널이 닫는다. 종료를 NIO graceful shutdown에 묶지 않는다.
            MainActor.assumeIsolated { try? self?.devices.save() }
        }
    }

    /// 손상(한쪽 파일만 있음·읽기 실패)이면 기존 파일을 덮어쓰지 않고 이번 실행만 임시 CA를 쓴다.
    /// ponytail: 임시 CA 사용을 UI에 알리지 않음. 인증서 화면(Task 15)에서 표시.
    private static func loadOrCreateCA() -> CertificateAuthority {
        do {
            if let ca = try CertificateAuthority.load(from: caDirectory) { return ca }
            let ca = try CertificateAuthority.generate()
            try? ca.save(to: caDirectory)
            return ca
        } catch {
            guard let ca = try? CertificateAuthority.generate() else { fatalError("CA 생성 실패: \(error)") }
            return ca
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

    func applySettingsToServer() async {
        await server?.update(sslPolicy: settings.sslPolicy)
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
        await applySettingsToServer()
    }

    func clear() {
        session.clear()
        selectedFlowID = nil
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
}
