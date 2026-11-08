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
    /// 필터 바 프로토콜 묶음. 비면 전체, 안에서는 OR.
    public var protocols: Set<FlowProtocol> = []
    /// 필터 바 콘텐츠 종류 묶음. 비면 전체, 안에서는 OR.
    public var contentKinds: Set<ContentKind> = []
    /// 필터 바 상태 코드 묶음(1...5 = 1xx...5xx). 비어 있지 않으면 응답 없는 흐름은 빠진다.
    public var statusClasses: Set<Int> = []

    /// 필터 바의 세 묶음이 모두 비었는가(= All).
    public var isBarEmpty: Bool { protocols.isEmpty && contentKinds.isEmpty && statusClasses.isEmpty }

    /// 필터 바만 All로 되돌린다. 검색어·사이드바 조건은 그대로.
    public mutating func clearBar() {
        protocols = []; contentKinds = []; statusClasses = []
    }

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
        if !protocols.isEmpty, !protocols.contains(FlowProtocol.of(flow)) { return false }
        if !contentKinds.isEmpty, !contentKinds.contains(ContentKind.of(flow)) { return false }
        if !statusClasses.isEmpty, !(flow.response.map { statusClasses.contains($0.status / 100) } ?? false) { return false }
        if text.isEmpty { return true }
        let fields = [flow.request.url, flow.request.method, flow.response.map { String($0.status) } ?? "", flow.clientAddress]
        return text.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            fields.contains { $0.range(of: token, options: .caseInsensitive) != nil }
        }
    }
}
