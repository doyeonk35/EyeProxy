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
}
@Test func saveAndLoadRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
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

private func tempDir() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }

@Test func ipLiteralsGetIPAddressSAN() throws {
    let ca = try CertificateAuthority.generate()
    for (host, bytes) in [("192.168.0.7", [192, 168, 0, 7] as [UInt8]), ("::1", [UInt8](repeating: 0, count: 15) + [1])] {
        let cert = try Certificate(derEncoded: ca.leaf(for: host).certificateDER)
        let sans = try #require(try cert.extensions.subjectAlternativeNames)
        #expect(sans.contains(.ipAddress(ASN1OctetString(contentBytes: bytes[...]))))
        #expect(!sans.contains(.dnsName(host)))
    }
    let bracketed = try Certificate(derEncoded: ca.leaf(for: "[::1]").certificateDER)
    #expect(try bracketed.extensions.subjectAlternativeNames?.contains(.ipAddress(ASN1OctetString(contentBytes: ([UInt8](repeating: 0, count: 15) + [1])[...]))) == true)
}
@Test func keyFileIs0600() throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    try CertificateAuthority.generate().save(to: dir)
    let attrs = try FileManager.default.attributesOfItem(atPath: dir.appending(path: "ca-key.pem").path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
@Test func loadNilWhenEmptyAndThrowsWhenPartial() throws {
    let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    #expect(try CertificateAuthority.load(from: dir) == nil)
    try CertificateAuthority.generate().certificatePEM.write(to: dir.appending(path: "ca.pem"), atomically: true, encoding: .utf8)
    #expect(throws: (any Error).self) { try CertificateAuthority.load(from: dir) }
}
@Test func leafValidityIs397DaysAndHostIsNormalized() throws {
    let ca = try CertificateAuthority.generate()
    let a = try ca.leaf(for: "API.Tving.com.")
    let cert = try Certificate(derEncoded: a.certificateDER)
    let days = cert.notValidAfter.timeIntervalSince(cert.notValidBefore) / 86400
    #expect(abs(days - (397 + 1.0 / 24)) < 0.01)
    #expect(try cert.extensions.subjectAlternativeNames == SubjectAlternativeNames([.dnsName("api.tving.com")]))
    #expect(cert.issuer == (try Certificate(derEncoded: ca.certificateDER)).subject)
}
