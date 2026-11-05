import Foundation
import EyeProxyCore

extension Flow {
    static func fixture(client: String, decrypted: Bool) -> Flow {
        Flow(id: FlowID(), clientAddress: client, startedAt: .now,
             request: FlowRequest(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/", headers: [], body: Data()),
             isDecrypted: decrypted)
    }
}
