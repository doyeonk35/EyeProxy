import EyeProxyCore
import Foundation

/// 사이드바 트리에서 선택한 행이 가리키는 범위.
public struct FlowScope: Hashable, Sendable {
    public var device: String?
    public var process: String?
    public var host: String?

    public init(device: String? = nil, process: String? = nil, host: String? = nil) {
        self.device = device
        self.process = process
        self.host = host
    }
}

public struct FlowFilter: Equatable, Sendable {
    public static let unknownProcessKey = "unknown"

    public var text: String = ""
    public var device: String? = nil
    public var host: String? = nil
    /// ProcessIdentity.groupKey. 귀속 없는 흐름의 키는 `unknownProcessKey`.
    public var process: String? = nil
    /// false면 `.hidden` 주석이 있는 흐름(Block List의 숨김)을 뺀다.
    public var includeHidden = false

    public init(text: String = "", device: String? = nil, host: String? = nil) {
        self.text = text
        self.device = device
        self.host = host
    }

    public static func isLoopback(_ address: String) -> Bool { address == "127.0.0.1" || address == "::1" }

    public static func sameDevice(_ a: String, _ b: String) -> Bool {
        (isLoopback(a) && isLoopback(b)) || a == b
    }

    public func matches(_ flow: Flow) -> Bool { matches(flow, process: nil) }

    /// process: 그 흐름의 groupKey(귀속 없으면 nil).
    public func matches(_ flow: Flow, process: String?) -> Bool {
        if !includeHidden, flow.annotations.contains(.hidden) { return false }
        if let device, !Self.sameDevice(flow.clientAddress, device) { return false }
        if let wanted = self.process, (process ?? Self.unknownProcessKey) != wanted { return false }
        if let host, flow.request.host != host { return false }
        if text.isEmpty { return true }
        let fields = [flow.request.url, flow.request.method, flow.response.map { String($0.status) } ?? "", flow.clientAddress]
        return text.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            fields.contains { $0.range(of: token, options: .caseInsensitive) != nil }
        }
    }
}
