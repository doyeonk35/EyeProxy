import Foundation
@testable import EyeProxyCore

extension FlowRequest {
    static func get(_ url: String) -> FlowRequest {
        let u = URL(string: url)!
        let scheme = u.scheme ?? "http"
        var path = u.path.isEmpty ? "/" : u.path
        if let q = u.query { path += "?" + q }
        return FlowRequest(method: "GET", scheme: scheme, host: u.host ?? "", port: u.port ?? (scheme == "https" ? 443 : 80),
                           path: path, headers: [], body: Data())
    }

    func with(headers: [HTTPHeader]) -> FlowRequest {
        var r = self
        r.headers = headers
        return r
    }
}
