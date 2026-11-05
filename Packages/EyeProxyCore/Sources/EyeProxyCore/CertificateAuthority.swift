import Foundation
import Synchronization
import X509
import SwiftASN1
import Crypto

public struct LeafCertificate: Sendable {
    public let certificateDER: [UInt8]
    public let privateKeyDER: [UInt8]   // PKCS#8
}

public final class CertificateAuthority: Sendable {
    private let key: P256.Signing.PrivateKey
    private let certificate: Certificate
    private let cache = Mutex<[String: LeafCertificate]>([:])
    public let certificateDER: [UInt8]

    private init(key: P256.Signing.PrivateKey, certificate: Certificate) throws {
        self.key = key
        self.certificate = certificate
        var s = DER.Serializer(); try s.serialize(certificate)
        certificateDER = s.serializedBytes
    }

    public static func generate(commonName: String = "EyeProxy Root CA", validYears: Int = 10) throws -> CertificateAuthority {
        let key = P256.Signing.PrivateKey()
        let name = try DistinguishedName { CommonName(commonName); OrganizationName("EyeProxy") }
        let now = Date()
        let cert = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-3600), notValidAfter: now.addingTimeInterval(Double(validYears) * 365 * 86400),
            issuer: name, subject: name,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                SubjectKeyIdentifier(hash: Certificate.PublicKey(key.publicKey))
            },
            issuerPrivateKey: .init(key))
        return try CertificateAuthority(key: key, certificate: cert)
    }

    public static func load(from directory: URL) throws -> CertificateAuthority? {
        guard let certPEM = try? String(contentsOf: directory.appending(path: "ca.pem"), encoding: .utf8),
              let keyPEM = try? String(contentsOf: directory.appending(path: "ca-key.pem"), encoding: .utf8)
        else { return nil }
        return try CertificateAuthority(key: P256.Signing.PrivateKey(pemRepresentation: keyPEM),
                                        certificate: Certificate(pemEncoded: certPEM))
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try certificatePEM.write(to: directory.appending(path: "ca.pem"), atomically: true, encoding: .utf8)
        let keyURL = directory.appending(path: "ca-key.pem")
        try key.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }

    public var certificatePEM: String { (try? certificate.serializeAsPEM().pemString) ?? "" }
    public var commonName: String {
        for rdn in certificate.subject { for a in rdn where a.type == .RDNAttributeType.commonName {
            if let s = String(a.value) { return s }
        } }
        return ""
    }

    public func leaf(for host: String) throws -> LeafCertificate {
        if let hit = cache.withLock({ $0[host] }) { return hit }
        let leafKey = P256.Signing.PrivateKey()
        let now = Date()
        let cert = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(leafKey.publicKey),
            notValidBefore: now.addingTimeInterval(-3600), notValidAfter: now.addingTimeInterval(397 * 86400),
            issuer: certificate.subject, subject: try DistinguishedName { CommonName(host) },
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([Self.generalName(for: host)])
            },
            issuerPrivateKey: .init(key))
        var s = DER.Serializer(); try s.serialize(cert)
        let leaf = LeafCertificate(certificateDER: s.serializedBytes, privateKeyDER: Array(leafKey.derRepresentation))
        // 동시 호출 경쟁 시 먼저 저장된 값을 돌려줘 동일 host는 항상 같은 값
        return cache.withLock { c in
            if let existing = c[host] { return existing }
            c[host] = leaf
            return leaf
        }
    }

    private static func generalName(for host: String) -> GeneralName {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            return .ipAddress(ASN1OctetString(contentBytes: withUnsafeBytes(of: &v4) { Array($0) }[...]))
        }
        if inet_pton(AF_INET6, host, &v6) == 1 {
            return .ipAddress(ASN1OctetString(contentBytes: withUnsafeBytes(of: &v6) { Array($0) }[...]))
        }
        return .dnsName(host)
    }
}
