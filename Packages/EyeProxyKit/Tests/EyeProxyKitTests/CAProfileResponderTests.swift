import Foundation
import Testing
import EyeProxyCore
@testable import EyeProxyKit

private func req(host: String, path: String, port: Int = 80) -> FlowRequest {
    FlowRequest(method: "GET", scheme: "http", host: host, port: port, path: path, headers: [], body: Data())
}
private let ctx = FlowContext(id: .init(), clientAddress: "1.2.3.4")

@Test func responderServesProfileOnEyeproxySSL() async throws {
    let ca = try CertificateAuthority.generate()
    let r = CAProfileResponder(certificateAuthority: ca)
    guard case .respond(let res) = await r.intercept(req(host: "eyeproxy", path: "/ssl"), context: ctx) else { Issue.record("x"); return }
    #expect(res.status == 200 && res.header("Content-Type") == "application/x-apple-aspen-config")
    #expect(res.header("Content-Disposition") == "attachment; filename=\"EyeProxy-CA.mobileconfig\"")
    #expect(res.body == MobileConfig.caProfile(certificateDER: ca.certificateDER, commonName: ca.commonName))
}

@Test func responderServesIndexAndNotFound() async throws {
    let r = CAProfileResponder(certificateAuthority: try CertificateAuthority.generate())
    guard case .respond(let home) = await r.intercept(req(host: "EyeProxy", path: "/", port: 9090), context: ctx) else { Issue.record("x"); return }
    #expect(home.status == 200 && String(decoding: home.body, as: UTF8.self).contains("<a href=\"/ssl\">"))
    guard case .respond(let nf) = await r.intercept(req(host: "eyeproxy", path: "/nope"), context: ctx) else { Issue.record("x"); return }
    #expect(nf.status == 404)
}

@Test func responderIgnoresOtherHosts() async throws {
    let r = CAProfileResponder(certificateAuthority: try CertificateAuthority.generate())
    let q = req(host: "example.com", path: "/ssl")
    guard case .continue(let out) = await r.intercept(q, context: ctx) else { Issue.record("x"); return }
    #expect(out == q)
}
