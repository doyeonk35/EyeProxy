import EyeProxyCore
import Foundation

/// Compose·Repeat 전송. 요청은 EyeProxy 프록시(127.0.0.1:proxyPort)를 거쳐 나가므로 메인 목록에 기록되고 모든 도구가 적용된다.
/// 서버 신뢰: 시스템 루트 + EyeProxy 루트(복호화된 호스트의 위조 인증서용). 그 밖의 인증서는 거부한다.
/// 리다이렉트는 따라가지 않는다(서버가 준 응답을 그대로 보여 준다).
public struct ComposeClient: Sendable {
    public let proxyPort: Int
    public let trustRootDER: [UInt8]

    public init(proxyPort: Int, trustRootDER: [UInt8]) {
        self.proxyPort = proxyPort
        self.trustRootDER = trustRootDER
    }

    public enum Failure: Error, Equatable { case badURL, notHTTP }

    /// `timeout`이 nil이면 기다리는 시간 제한이 없다.
    public func send(_ request: FlowRequest, timeout: TimeInterval?) async throws -> FlowResponse {
        guard let url = URL(string: request.url) else { throw Failure.badURL }
        let limit = timeout ?? .greatestFiniteMagnitude
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: "127.0.0.1", kCFNetworkProxiesHTTPPort: proxyPort,
            kCFNetworkProxiesHTTPSEnable: 1, kCFNetworkProxiesHTTPSProxy: "127.0.0.1", kCFNetworkProxiesHTTPSPort: proxyPort,
        ]
        config.timeoutIntervalForRequest = limit
        config.timeoutIntervalForResource = limit
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: Delegate(rootDER: trustRootDER), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        // 캐시는 urlCache = nil로 끈다. reloadIgnoring… 정책은 Cache-Control·Pragma를 몰래 붙이므로 쓰지 않는다.
        var r = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: limit)
        r.httpMethod = request.method
        for h in request.headers where !Self.managedHeaders.contains(h.name.lowercased()) {
            r.addValue(h.value, forHTTPHeaderField: h.name)
        }
        if !request.body.isEmpty { r.httpBody = request.body }
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        // URLSession이 본문 압축을 풀었으므로 Content-Encoding·Length는 뺀다(원본은 메인 목록의 흐름에 남는다).
        let headers = http.allHeaderFields.compactMap { k, v -> HTTPHeader? in
            let name = "\(k)"
            return ["content-encoding", "content-length"].contains(name.lowercased()) ? nil : HTTPHeader(name: name, value: "\(v)")
        }
        return FlowResponse(status: http.statusCode, reason: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                            headers: headers, body: data)
    }

    /// URLSession이 직접 정하는 헤더(사용자 값은 무시되거나 충돌한다).
    private static let managedHeaders: Set<String> = ["host", "content-length", "connection", "proxy-connection", "transfer-encoding"]
}

private final class Delegate: NSObject, URLSessionTaskDelegate, Sendable {
    let rootDER: [UInt8]
    init(rootDER: [UInt8]) { self.rootDER = rootDER }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        if let root = SecCertificateCreateWithData(nil, Data(rootDER) as CFData) {
            SecTrustSetAnchorCertificates(trust, [root] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)   // 시스템 루트도 계속 신뢰(복호화하지 않는 호스트)
        }
        guard SecTrustEvaluateWithError(trust, nil) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
