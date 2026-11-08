import EyeProxyCore
import Foundation

/// host == "eyeproxy"·"prog"(대소문자·포트 무관) 요청에 응답: "/ssl" → CA 프로파일(Android UA면 PEM), "/ssl.crt"·"/ssl.pem" → PEM, "/ssl.cer" → DER, "/" → 안내, 그 외 404.
public struct CAProfileResponder: RequestInterceptor {
    private let profile: Data
    private let pem: Data
    private let der: Data
    private let fingerprint: String

    public init(certificateAuthority: CertificateAuthority) {
        profile = MobileConfig.caProfile(certificateDER: certificateAuthority.certificateDER, commonName: certificateAuthority.commonName)
        pem = Data(certificateAuthority.certificatePEM.utf8)
        der = Data(certificateAuthority.certificateDER)
        fingerprint = certificateAuthority.sha256Fingerprint
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        guard ["eyeproxy", "prog"].contains(request.host.lowercased()) else { return .continue(request) }
        switch request.path {
        case "/ssl" where request.header("User-Agent")?.lowercased().contains("android") == true, "/ssl.crt", "/ssl.pem":
            return pemResponse()
        case "/ssl":
            return .respond(FlowResponse(status: 200, reason: "OK", headers: [
                HTTPHeader(name: "Content-Type", value: "application/x-apple-aspen-config"),
                HTTPHeader(name: "Content-Disposition", value: "attachment; filename=\"EyeProxy-CA.mobileconfig\""),
            ], body: profile))
        case "/ssl.cer":
            return derResponse()
        case "/":
            let html = """
            <!doctype html><meta charset="utf-8"><title>EyeProxy</title>\
            <p><a href="/ssl">EyeProxy CA 프로파일 설치</a> (iOS·macOS 프로파일)</p>\
            <p><a href="/ssl.crt">CA 인증서 PEM</a> (Android·기타)</p>\
            <p><a href="/ssl.cer">CA 인증서 DER</a></p>\
            <p>SHA-256: <code>\(fingerprint)</code></p>
            """
            return .respond(FlowResponse(status: 200, reason: "OK", headers: [HTTPHeader(name: "Content-Type", value: "text/html; charset=utf-8")], body: Data(html.utf8)))
        default:
            return .respond(FlowResponse(status: 404, reason: "Not Found", headers: [HTTPHeader(name: "Content-Type", value: "text/plain")], body: Data("Not Found".utf8)))
        }
    }

    private func pemResponse() -> RequestDecision {
        .respond(FlowResponse(status: 200, reason: "OK", headers: [
            HTTPHeader(name: "Content-Type", value: "application/x-x509-ca-cert"),
            HTTPHeader(name: "Content-Disposition", value: "attachment; filename=\"EyeProxy-CA.crt\""),
        ], body: pem))
    }

    private func derResponse() -> RequestDecision {
        .respond(FlowResponse(status: 200, reason: "OK", headers: [
            HTTPHeader(name: "Content-Type", value: "application/pkix-cert"),
            HTTPHeader(name: "Content-Disposition", value: "attachment; filename=\"EyeProxy-CA.cer\""),
        ], body: der))
    }
}
