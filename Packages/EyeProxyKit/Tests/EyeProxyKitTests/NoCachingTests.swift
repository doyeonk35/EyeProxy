import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private let ctx = FlowContext(id: .init(), clientAddress: "127.0.0.1", clientPort: 5000) { _ in }

@Test func noCachingRequestHeaders() async {
    let req = FlowRequest(method: "GET", scheme: "https", host: "img.example.com", port: 443, path: "/", headers: [
        HTTPHeader(name: "if-none-match", value: "x"), HTTPHeader(name: "If-Modified-Since", value: "y"),
        HTTPHeader(name: "cache-control", value: "max-age=60"), HTTPHeader(name: "Accept", value: "*/*"),
    ], body: Data())
    guard case .continue(let out) = await NoCachingInterceptor().intercept(req, context: ctx) else { Issue.record("dropped"); return }
    #expect(out.headers == [HTTPHeader(name: "Accept", value: "*/*"),
                            HTTPHeader(name: "Pragma", value: "no-cache"), HTTPHeader(name: "Cache-Control", value: "no-cache")])
}

@Test func noCachingResponseHeaders() async {
    let req = FlowRequest(method: "GET", scheme: "https", host: "img.example.com", port: 443, path: "/", headers: [], body: Data())
    let res = FlowResponse(status: 200, reason: "OK", headers: [
        HTTPHeader(name: "ETag", value: "a"), HTTPHeader(name: "last-modified", value: "b"), HTTPHeader(name: "Expires", value: "c"),
        HTTPHeader(name: "Cache-Control", value: "max-age=1"), HTTPHeader(name: "Content-Type", value: "text/plain"),
    ], body: Data())
    guard case .continue(let out) = await NoCachingInterceptor().intercept(res, for: req, context: ctx) else { Issue.record("dropped"); return }
    #expect(out.headers == [HTTPHeader(name: "Content-Type", value: "text/plain"),
                            HTTPHeader(name: "Expires", value: "0"), HTTPHeader(name: "Cache-Control", value: "no-cache")])
}
