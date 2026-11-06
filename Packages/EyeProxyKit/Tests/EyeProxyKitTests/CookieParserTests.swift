import EyeProxyCore
import Testing
@testable import EyeProxyKit

@Test func cookieParserTolerates() {
    #expect(CookieParser.requestCookies(" a=1;  b=x=y;;novalue ; ") == [.init(name: "a", value: "1"), .init(name: "b", value: "x=y"), .init(name: "novalue", value: "")])
    #expect(CookieParser.responseCookies(["sid=abc; Path=/; HttpOnly", "bad"]) == [.init(name: "sid", value: "abc; Path=/; HttpOnly"), .init(name: "bad", value: "")])
}
