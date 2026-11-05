import Testing
import Foundation
import X509
import SwiftASN1
import Crypto
@testable import EyeProxyCore

@Test func generatedCAIsSelfSignedCA() throws {
    let ca = try CertificateAuthority.generate()
    let cert = try Certificate(derEncoded: ca.certificateDER)
    #expect(cert.issuer == cert.subject)
    #expect(try cert.extensions.basicConstraints == .isCertificateAuthority(maxPathLength: nil))
}
@Test func leafIsSignedByCAAndHasSAN() throws {
    let ca = try CertificateAuthority.generate()
    let leaf = try ca.leaf(for: "api.tving.com")
    let cert = try Certificate(derEncoded: leaf.certificateDER)
    let caCert = try Certificate(derEncoded: ca.certificateDER)
    #expect(cert.issuer == caCert.subject)
    #expect(try cert.extensions.subjectAlternativeNames?.contains(.dnsName("api.tving.com")) == true)
    #expect(try cert.extensions.extendedKeyUsage?.contains(.serverAuth) == true)
    #expect(try leaf.certificateDER == ca.leaf(for: "api.tving.com").certificateDER)  // 캐시
}
@Test func saveAndLoadRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let ca = try CertificateAuthority.generate(); try ca.save(to: dir)
    let loaded = try #require(try CertificateAuthority.load(from: dir))
    #expect(loaded.certificateDER == ca.certificateDER)
    #expect(try loaded.leaf(for: "a").certificateDER != [])   // 로드한 키로 발급 가능
}
@Test func leafChainVerifiesAgainstCA() async throws {
    let ca = try CertificateAuthority.generate()
    let leaf = try Certificate(derEncoded: try ca.leaf(for: "h").certificateDER)
    var verifier = Verifier(rootCertificates: CertificateStore([try Certificate(derEncoded: ca.certificateDER)])) { RFC5280Policy() }
    let result = await verifier.validate(leaf: leaf, intermediates: CertificateStore())
    guard case .validCertificate = result else { Issue.record("\(result)"); return }
}
