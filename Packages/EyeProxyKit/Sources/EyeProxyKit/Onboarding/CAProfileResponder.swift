import EyeProxyCore
import Foundation

/// host == "eyeproxy"(포트 무관) 요청에 응답: "/ssl" → CA 프로파일, "/" → 안내, 그 외 404.
public struct CAProfileResponder: RequestInterceptor {
    private let profile: Data

    public init(certificateAuthority: CertificateAuthority) {
        profile = MobileConfig.caProfile(certificateDER: certificateAuthority.certificateDER, commonName: certificateAuthority.commonName)
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        guard request.host.lowercased() == "eyeproxy" else { return .continue(request) }
        switch request.path {
        case "/ssl":
            return .respond(FlowResponse(status: 200, reason: "OK", headers: [
                HTTPHeader(name: "Content-Type", value: "application/x-apple-aspen-config"),
                HTTPHeader(name: "Content-Disposition", value: "attachment; filename=\"EyeProxy-CA.mobileconfig\""),
            ], body: profile))
        case "/":
            let html = "<!doctype html><meta charset=\"utf-8\"><title>EyeProxy</title><p><a href=\"/ssl\">EyeProxy CA 프로파일 설치</a></p>"
            return .respond(FlowResponse(status: 200, reason: "OK", headers: [HTTPHeader(name: "Content-Type", value: "text/html; charset=utf-8")], body: Data(html.utf8)))
        default:
            return .respond(FlowResponse(status: 404, reason: "Not Found", headers: [HTTPHeader(name: "Content-Type", value: "text/plain")], body: Data("Not Found".utf8)))
        }
    }
}
