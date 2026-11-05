import Foundation

public struct FlowID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init() { rawValue = UUID() }
}

public struct HTTPHeader: Equatable, Codable, Sendable {
    public var name: String
    public var value: String
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct FlowRequest: Equatable, Codable, Sendable {
    public var method: String
    public var scheme: String
    public var host: String
    public var port: Int
    public var path: String
    public var headers: [HTTPHeader]
    public var body: Data

    public init(method: String, scheme: String, host: String, port: Int, path: String, headers: [HTTPHeader], body: Data) {
        self.method = method
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// 기본 포트(http 80, https 443)면 포트를 생략한다.
    public var url: String {
        let isDefault = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        return "\(scheme)://\(host)\(isDefault ? "" : ":\(port)")\(path)"
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public struct FlowResponse: Equatable, Codable, Sendable {
    public var status: Int
    public var reason: String
    public var headers: [HTTPHeader]
    public var body: Data

    public init(status: Int, reason: String, headers: [HTTPHeader], body: Data) {
        self.status = status
        self.reason = reason
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public struct ConnectionLogEntry: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let clientAddress: String
    public let host: String
    public let port: Int
    public let message: String

    public init(id: UUID, date: Date, clientAddress: String, host: String, port: Int, message: String) {
        self.id = id
        self.date = date
        self.clientAddress = clientAddress
        self.host = host
        self.port = port
        self.message = message
    }
}

public struct Flow: Equatable, Codable, Sendable, Identifiable {
    public let id: FlowID
    public let clientAddress: String
    /// 클라이언트 소켓의 로컬 포트 (프로세스 식별용). 이전 저장분 디코딩을 위해 옵셔널.
    public let clientPort: Int?
    public let startedAt: Date
    public var request: FlowRequest
    public var response: FlowResponse?
    public var completedAt: Date?
    public var error: String?
    /// https를 MITM 했으면 true
    public var isDecrypted: Bool
    /// CONNECT 패스스루 항목이면 true (request.method == "CONNECT")
    public var isTunnel: Bool

    public init(id: FlowID, clientAddress: String, clientPort: Int? = nil, startedAt: Date, request: FlowRequest, response: FlowResponse? = nil,
                completedAt: Date? = nil, error: String? = nil, isDecrypted: Bool = false, isTunnel: Bool = false) {
        self.id = id
        self.clientAddress = clientAddress
        self.clientPort = clientPort
        self.startedAt = startedAt
        self.request = request
        self.response = response
        self.completedAt = completedAt
        self.error = error
        self.isDecrypted = isDecrypted
        self.isTunnel = isTunnel
    }
}

public enum FlowEvent: Sendable {
    case requestStarted(Flow)
    case responseReceived(id: FlowID, response: FlowResponse, completedAt: Date)
    case failed(id: FlowID, error: String, completedAt: Date)
    case connectionLog(ConnectionLogEntry)
}
