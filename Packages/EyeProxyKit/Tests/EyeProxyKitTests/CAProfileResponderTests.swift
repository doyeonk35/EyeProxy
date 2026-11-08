import Foundation
import Testing
import EyeProxyCore
@testable import EyeProxyKit

private func req(host: String, path: String, port: Int = 80, headers: [HTTPHeader] = []) -> FlowRequest {
    FlowRequest(method: "GET", scheme: "http", host: host, port: port, path: path, headers: headers, body: Data())
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

@Test func sslServesPEMForAndroidUserAgent() async throws {
    let ca = try CertificateAuthority.generate()
    let r = CAProfileResponder(certificateAuthority: ca)
    let android = [HTTPHeader(name: "User-Agent", value: "Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/120")]
    guard case .respond(let pem) = await r.intercept(req(host: "eyeproxy", path: "/ssl", headers: android), context: ctx) else { Issue.record("x"); return }
    #expect(pem.status == 200 && pem.header("Content-Type") == "application/x-x509-ca-cert")
    #expect(pem.body == Data(ca.certificatePEM.utf8))
    let ios = [HTTPHeader(name: "user-agent", value: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1")]
    guard case .respond(let mc) = await r.intercept(req(host: "eyeproxy", path: "/ssl", headers: ios), context: ctx) else { Issue.record("x"); return }
    #expect(mc.status == 200 && mc.header("Content-Type") == "application/x-apple-aspen-config")
    #expect(mc.body == MobileConfig.caProfile(certificateDER: ca.certificateDER, commonName: ca.commonName))
}

@Test func sslCrtPemCerPathsServeBytes() async throws {
    let ca = try CertificateAuthority.generate()
    let r = CAProfileResponder(certificateAuthority: ca)
    for path in ["/ssl.crt", "/ssl.pem"] {
        guard case .respond(let res) = await r.intercept(req(host: "eyeproxy", path: path), context: ctx) else { Issue.record("x"); return }
        #expect(res.status == 200 && res.header("Content-Type") == "application/x-x509-ca-cert")
        #expect(res.header("Content-Disposition") == "attachment; filename=\"EyeProxy-CA.crt\"")
        #expect(res.body == Data(ca.certificatePEM.utf8))
    }
    guard case .respond(let der) = await r.intercept(req(host: "eyeproxy", path: "/ssl.cer"), context: ctx) else { Issue.record("x"); return }
    #expect(der.status == 200 && der.header("Content-Type") == "application/pkix-cert")
    #expect(der.header("Content-Disposition") == "attachment; filename=\"EyeProxy-CA.cer\"")
    #expect(der.body == Data(ca.certificateDER))
}

@Test func progHostIsAlias() async throws {
    let r = CAProfileResponder(certificateAuthority: try CertificateAuthority.generate())
    for host in ["prog", "PROG"] {
        guard case .respond(let res) = await r.intercept(req(host: host, path: "/ssl"), context: ctx) else { Issue.record("x"); return }
        #expect(res.status == 200)
    }
    guard case .continue = await r.intercept(req(host: "prog.example.com", path: "/ssl"), context: ctx) else { Issue.record("x"); return }
}

@Test func indexListsLinksAndFingerprint() async throws {
    let ca = try CertificateAuthority.generate()
    let r = CAProfileResponder(certificateAuthority: ca)
    guard case .respond(let home) = await r.intercept(req(host: "eyeproxy", path: "/"), context: ctx) else { Issue.record("x"); return }
    let html = String(decoding: home.body, as: UTF8.self)
    for s in ["\"/ssl\"", "\"/ssl.crt\"", "\"/ssl.cer\"", ca.sha256Fingerprint] { #expect(html.contains(s)) }
}
