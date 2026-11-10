import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func h(_ n: String, _ v: String) -> HTTPHeader { .init(name: n, value: v) }
private func req(_ headers: [HTTPHeader] = [], body: String = "", method: String = "GET", scheme: String = "https",
                 host: String = "example.com", port: Int = 443, path: String = "/") -> FlowRequest {
    FlowRequest(method: method, scheme: scheme, host: host, port: port, path: path, headers: headers, body: Data(body.utf8))
}

@Test func requestTabsShowConditionalOnesOnlyWithContent() {
    #expect(DetailTabs.request(req()) == [[.header, .query, .body, .raw], [.summary, .treeview, .json]])
    let all = [h("content-type", "application/x-www-form-urlencoded; charset=utf-8"), h("Cookie", "a=1"), h("authorization", "Bearer x")]
    // 요청 쪽은 M3U8 탭이 없다(재생목록은 응답 본문) — 판정 R13.
    #expect(DetailTabs.request(req(all, body: "a=1"))
        == [[.header, .query, .body, .form, .cookies, .auth, .raw], [.summary, .treeview, .json]])
    #expect(DetailTabs.request(req([h("Content-Type", "multipart/form-data; boundary=x")], body: "--x--"))[0].contains(.form))
    // 폼 Content-Type이어도 본문이 비면, JSON 본문이면, 빈 Cookie 헤더면 탭이 없다.
    #expect(!DetailTabs.request(req(all))[0].contains(.form))
    #expect(!DetailTabs.request(req([h("Content-Type", "application/json")], body: "{}"))[0].contains(.form))
    #expect(!DetailTabs.request(req([h("Cookie", " ")]))[0].contains(.cookies))
    #expect(DetailTab.allCases.map(\.title) == ["Header", "Query", "Body", "Form", "Cookies", "Auth", "Set-Cookie", "Raw",
                                                "Summary", "Treeview", "M3U8", "JSON"])
}

@Test func responseTabsShowSetCookieAndM3U8OnlyWhenPresent() {
    let plain = FlowResponse(status: 200, reason: "OK", headers: [h("Content-Type", "text/plain")], body: Data())
    #expect(DetailTabs.response(plain, isPlaylist: false) == [[.header, .body, .raw], [.treeview, .json]])
    let cookie = FlowResponse(status: 200, reason: "OK", headers: [h("set-cookie", "a=1; Path=/")], body: Data())
    #expect(DetailTabs.response(cookie, isPlaylist: true) == [[.header, .body, .setCookie, .raw], [.treeview, .m3u8, .json]])
}

@Test func chosenTabFallsBackToHeaderWhenAbsent() {
    let tabs = DetailTabs.request(req())
    #expect(DetailTabs.shown(.summary, in: tabs) == .summary)
    #expect(DetailTabs.shown(.auth, in: tabs) == .header)
    #expect(DetailTabs.shown(.m3u8, in: tabs) == .header)
}

@Test func urlPartsSplitSchemeHostPortRest() {
    #expect(URLParts(req(path: "/a/b?x=1&y")) == URLParts(scheme: "https://", host: "example.com", port: "", rest: "/a/b?x=1&y"))
    #expect(URLParts(req(scheme: "http", port: 8080, path: "/")) == URLParts(scheme: "http://", host: "example.com", port: ":8080", rest: "/"))
    // CONNECT 터널: 스킴·경로 없이 host:port.
    #expect(URLParts(req(method: "CONNECT", path: "")) == URLParts(scheme: "", host: "example.com", port: ":443", rest: ""))
}

@Test func tableFilterHonoursCaseAndRegexOptions() {
    let rows = [h("Content-Type", "text/html"), h("X-Id", "ABC-123"), h("accept", "*/*")]
    #expect(TableFilter().indices(of: rows, query: "") == [0, 1, 2])
    #expect(TableFilter().indices(of: rows, query: "content") == [0])  // 기본: 대소문자 무시, 이름 또는 값
    #expect(TableFilter().indices(of: rows, query: "abc") == [1])
    #expect(TableFilter(caseSensitive: true).indices(of: rows, query: "abc") == [])
    #expect(TableFilter(caseSensitive: true).indices(of: rows, query: "ABC") == [1])
    #expect(TableFilter(regex: true).indices(of: rows, query: #"^x-|\d{3}$"#) == [1])
    #expect(TableFilter(regex: true).indices(of: rows, query: "^ACCEPT$") == [2])
    #expect(TableFilter(caseSensitive: true, regex: true).indices(of: rows, query: "^ACCEPT$") == [])
    // Text 모드에서 정규식 문자는 글자 그대로.
    #expect(TableFilter().indices(of: rows, query: "*/*") == [2])
    // 틀린 정규식은 nil(화면은 오류 표시).
    #expect(TableFilter(regex: true).indices(of: rows, query: "(") == nil)
}

@Test func formFieldsParseURLEncodedAndMultipart() {
    #expect(FormFields.parse(body: Data("a=1&b=hello+world%21&c".utf8), contentType: "application/x-www-form-urlencoded")
        == [h("a", "1"), h("b", "hello world!"), h("c", "")])
    let multipart = "--XyZ\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n안녕\r\n"
        + "--XyZ\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.png\"\r\nContent-Type: image/png\r\n\r\n12345\r\n--XyZ--\r\n"
    #expect(FormFields.parse(body: Data(multipart.utf8), contentType: "multipart/form-data; boundary=\"XyZ\"")
        == [h("title", "안녕"), h("file", "a.png (5 bytes)")])
    #expect(FormFields.parse(body: Data("{}".utf8), contentType: "application/json") == [])
}

@Test func authRowsDecodeBasicAndShowOtherSchemes() {
    #expect(AuthFields.parse("Basic " + Data("user:pa:ss".utf8).base64EncodedString()) == [h("Type", "Basic"), h("Username", "user"), h("Password", "pa:ss")])
    #expect(AuthFields.parse("Bearer eyJ.abc") == [h("Type", "Bearer"), h("Token", "eyJ.abc")])
    #expect(AuthFields.parse("rawtoken") == [h("Token", "rawtoken")])
}

@Test func jsonDetectsBodyRegardlessOfContentType() throws {
    #expect(BodyDecoder.json(body: Data(#"{"a":[1]}"#.utf8), headers: [h("Content-Type", "text/plain")]) == "{\n  \"a\" : [\n    1\n  ]\n}")
    #expect(BodyDecoder.json(body: Data("hello".utf8), headers: []) == nil)
    #expect(BodyDecoder.json(body: Data(), headers: []) == nil)
}
