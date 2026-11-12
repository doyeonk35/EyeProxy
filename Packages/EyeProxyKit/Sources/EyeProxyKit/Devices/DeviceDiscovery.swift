import Foundation
import Network

/// Bonjour 광고(AirPlay·Companion·Google Cast)에서 같은 네트워크 기기의 이름을 찾는다.
/// 권한이 없거나 실패하면 조용히 넘긴다.
@MainActor
public final class DeviceDiscovery {
    public private(set) var isStarted = false
    private let onFound: @MainActor (DiscoveredDevice) -> Void
    private var browsers: [NWBrowser] = []

    public init(onFound: @escaping @MainActor (DiscoveredDevice) -> Void) {
        self.onFound = onFound
    }

    // MARK: 순수 함수

    public nonisolated static func parse(serviceType: String, serviceName: String, txt: [String: String]) -> (name: String, kind: DeviceKind?)? {
        let name: String
        let model: String?
        switch serviceType {
        case "_airplay._tcp": name = serviceName; model = txt["model"]
        case "_companion-link._tcp": name = serviceName; model = txt["rpMd"]
        case "_googlecast._tcp": name = txt["fn"] ?? ""; model = nil
        default: return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed, model.flatMap(kind(forModel:)))
    }

    public nonisolated static func normalize(_ address: String) -> String {
        address.hasPrefix("::ffff:") ? String(address.dropFirst(7)) : address
    }

    private nonisolated static func kind(forModel model: String) -> DeviceKind? {
        if model.hasPrefix("AppleTV") { return .appleTV }
        if model.hasPrefix("iPhone") { return .iPhone }
        if model.hasPrefix("iPad") { return .iPad }
        return nil
    }

    // MARK: 네트워크 (단위 테스트 없음)

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        for type in ["_airplay._tcp", "_companion-link._tcp", "_googlecast._tcp"] {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] _, changes in
                let results = changes.compactMap { change -> NWBrowser.Result? in
                    switch change {
                    case .added(let r), .changed(old: _, new: let r, flags: _): r
                    default: nil
                    }
                }
                Task { @MainActor in for r in results { self?.resolve(r, type: type) } }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    private func resolve(_ result: NWBrowser.Result, type: String) {
        guard case .service(let serviceName, _, _, _) = result.endpoint else { return }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata { txt = record.dictionary }
        guard let parsed = Self.parse(serviceType: type, serviceName: serviceName, txt: txt) else { return }

        // 프록시는 0.0.0.0에 묶여 있어 기기 주소는 늘 IPv4다. IPv6로 연결되면 맞출 수 없다.
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let conn = NWConnection(to: result.endpoint, using: params)
        let onFound = self.onFound
        // 한 번만 처리하고 닫는다.
        nonisolated(unsafe) var done = false
        let finish: @Sendable (String?) -> Void = { address in
            Task { @MainActor in
                guard !done else { return }
                done = true
                conn.cancel()
                if let address { onFound(DiscoveredDevice(address: address, name: parsed.name, kind: parsed.kind)) }
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var address: String?
                if case .hostPort(let host, _)? = conn.currentPath?.remoteEndpoint, case .ipv4(let v4) = host {
                    address = Self.normalize(v4.debugDescription.split(separator: "%").first.map(String.init) ?? "")
                }
                finish(address)
            case .failed, .cancelled: finish(nil)
            default: break
            }
        }
        conn.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(nil) }
    }
}
