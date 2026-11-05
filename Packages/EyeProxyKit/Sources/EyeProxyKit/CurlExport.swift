import EyeProxyCore
import Foundation

public enum CurlExport {
    public static func command(for request: FlowRequest) -> String {
        var parts = ["curl"]
        if request.method.uppercased() != "GET" { parts += ["-X", quote(request.method)] }
        parts.append(quote(request.url))
        for h in request.headers where !["content-length", "host"].contains(h.name.lowercased()) {
            parts += ["-H", quote("\(h.name): \(h.value)")]
        }
        var cmd = parts.joined(separator: " ")
        if !request.body.isEmpty {
            if let s = String(data: request.body, encoding: .utf8) { cmd += " --data-binary " + quote(s) }
            else { cmd += " # binary body omitted" }
        }
        return cmd
    }

    private static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
