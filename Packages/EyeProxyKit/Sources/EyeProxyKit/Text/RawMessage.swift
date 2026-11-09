import EyeProxyCore
import Foundation

/// 상세 Raw 탭(스펙 §7): HTTP/1.1 원문 — 시작 줄 + 헤더 + 빈 줄 + 본문. 표시용이라 줄바꿈은 `\n`.
/// 본문은 Content-Encoding을 풀어 UTF-8이면 텍스트, 아니면 `<binary N bytes>`. 헤더는 원래 값 그대로.
public enum RawMessage {
    public static func request(_ r: FlowRequest) -> String {
        text("\(r.method) \(r.path) HTTP/1.1", r.headers, r.body)
    }

    public static func response(_ r: FlowResponse) -> String {
        text("HTTP/1.1 \(r.status) \(r.reason)", r.headers, r.body)
    }

    private static func text(_ startLine: String, _ headers: [HTTPHeader], _ body: Data) -> String {
        let encoding = headers.first { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value
        let data = BodyDecoder.decompressed(body: body, contentEncoding: encoding) ?? body
        let bodyText = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        return ([startLine] + headers.map { "\($0.name): \($0.value)" } + ["", bodyText]).joined(separator: "\n")
    }
}
