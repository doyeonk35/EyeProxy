import EyeProxyCore
import Foundation

public enum CurlExport {
    /// `proxy`(예: `http://192.168.0.2:9090`)가 있으면 본문 앞에 `--proxy`를 붙인다(Tools ▸ Add --proxy flag into cURL command).
    public static func command(for request: FlowRequest, proxy: String? = nil) -> String {
        var parts = ["curl"]
        if request.method.uppercased() != "GET" { parts += ["-X", quote(request.method)] }
        parts.append(quote(request.url))
        for h in request.headers where !["content-length", "host"].contains(h.name.lowercased()) {
            parts += ["-H", quote("\(h.name): \(h.value)")]
        }
        if let proxy { parts += ["--proxy", quote(proxy)] }
        var cmd = parts.joined(separator: " ")
        if !request.body.isEmpty {
            if let s = String(data: request.body, encoding: .utf8) { cmd += " --data-binary " + quote(s) }
            else { cmd += " # binary body omitted" }
        }
        return cmd
    }

    private static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
