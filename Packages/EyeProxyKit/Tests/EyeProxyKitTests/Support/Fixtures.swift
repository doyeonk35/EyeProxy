import Foundation
import EyeProxyCore

extension Flow {
    static func fixture(client: String, decrypted: Bool) -> Flow {
        Flow(id: FlowID(), clientAddress: client, startedAt: .now,
             request: FlowRequest(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/", headers: [], body: Data()),
             isDecrypted: decrypted)
    }
}

extension Flow {
    static func fixture(url: String, method: String, status: Int) -> Flow {
        let c = URLComponents(string: url)!
        var f = Flow.fixture(client: "192.168.0.21", decrypted: true)
        f.request = FlowRequest(method: method, scheme: c.scheme ?? "https", host: c.host ?? "", port: c.port ?? (c.scheme == "http" ? 80 : 443),
                                path: c.percentEncodedPath + (c.percentEncodedQuery.map { "?" + $0 } ?? ""), headers: [], body: Data())
        f.response = FlowResponse(status: status, reason: "", headers: [], body: Data())
        return f
    }
}
