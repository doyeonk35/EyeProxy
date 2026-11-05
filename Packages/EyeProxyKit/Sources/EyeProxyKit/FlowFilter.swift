import EyeProxyCore
import Foundation

public struct FlowFilter: Equatable, Sendable {
    public var text: String = ""
    public var device: String? = nil
    public var host: String? = nil

    public init(text: String = "", device: String? = nil, host: String? = nil) {
        self.text = text
        self.device = device
        self.host = host
    }

    public func matches(_ flow: Flow) -> Bool {
        if let device, flow.clientAddress != device { return false }
        if let host, flow.request.host != host { return false }
        let fields = [flow.request.url, flow.request.method, flow.response.map { String($0.status) } ?? "", flow.clientAddress]
        return text.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            fields.contains { $0.range(of: token, options: .caseInsensitive) != nil }
        }
    }
}
