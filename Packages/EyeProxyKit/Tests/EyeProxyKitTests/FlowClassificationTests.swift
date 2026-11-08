import EyeProxyCore
import Testing
@testable import EyeProxyKit

private func flow(path: String = "/", request: String? = nil, response: String?) -> Flow {
    var f = Flow.fixture(url: "https://api.example.com" + path, method: "POST", status: 200)
    if let request { f.request.headers = [HTTPHeader(name: "Content-Type", value: request)] }
    if let response { f.response?.headers = [HTTPHeader(name: "Content-Type", value: response)] }
    return f
}

@Test func protocolFollowsScheme() {
    #expect(FlowProtocol.of(Flow.fixture(url: "https://a.com/", method: "GET", status: 200)) == .https)
    #expect(FlowProtocol.of(Flow.fixture(url: "http://a.com/", method: "GET", status: 200)) == .http)
    var tunnel = Flow.fixture(client: "192.168.0.21", decrypted: false); tunnel.isTunnel = true
    #expect(FlowProtocol.of(tunnel) == .https)
}

@Test func contentKindPriority() {
    #expect(ContentKind.of(flow(path: "/api/graphql?x=1", response: "application/json")) == .graphql)
    #expect(ContentKind.of(flow(request: "multipart/form-data; boundary=x", response: "application/json")) == .form)
    #expect(ContentKind.of(flow(response: "application/vnd.api+json")) == .json)
    #expect(ContentKind.of(flow(response: "application/rss+xml")) == .xml)
    #expect(ContentKind.of(flow(response: "text/javascript")) == .js)
    #expect(ContentKind.of(flow(response: "text/css")) == .css)
    #expect(ContentKind.of(flow(response: "text/html")) == .document)
    #expect(ContentKind.of(flow(response: "image/png")) == .media)
    #expect(ContentKind.of(flow(response: "font/woff2")) == .media)
    #expect(ContentKind.of(flow(response: "application/x-mpegurl")) == .media)
    #expect(ContentKind.of(flow(response: "application/octet-stream")) == .other)
    #expect(ContentKind.of(flow(response: nil)) == .other)
}

@Test func contentKindIgnoresCaseAndParams() {
    #expect(ContentKind.of(flow(response: "Application/JSON; charset=utf-8")) == .json)
}

@Test func contentKindFallsBackToRequestTypeWhenNoResponse() {
    var f = flow(request: "application/json", response: nil); f.response = nil
    #expect(ContentKind.of(f) == .json)
}
