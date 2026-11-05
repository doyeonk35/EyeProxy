import Foundation
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
    public let certificateDER: [UInt8]
    public let certificatePEM: String

    private init(key: P256.Signing.PrivateKey, certificate: Certificate) throws {
        self.key = key
        self.certificate = certificate
        var s = DER.Serializer(); try s.serialize(certificate)
        certificateDER = s.serializedBytes
        certificatePEM = try certificate.serializeAsPEM().pemString
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
        let certURL = directory.appending(path: "ca.pem"), keyURL = directory.appending(path: "ca-key.pem")
        let fm = FileManager.default
        switch (fm.fileExists(atPath: certURL.path), fm.fileExists(atPath: keyURL.path)) {
        case (false, false): return nil
        case (true, true): break
        default: throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])  // 한쪽만 있으면 손상 상태
        }
        return try CertificateAuthority(
            key: P256.Signing.PrivateKey(pemRepresentation: String(contentsOf: keyURL, encoding: .utf8)),
            certificate: Certificate(pemEncoded: String(contentsOf: certURL, encoding: .utf8)))
    }

    public func save(to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // 키를 먼저, 처음부터 0600으로 생성
        let keyURL = directory.appending(path: "ca-key.pem")
        guard fm.createFile(atPath: keyURL.path, contents: Data(key.pemRepresentation.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: keyURL.path])
        }
        try certificatePEM.write(to: directory.appending(path: "ca.pem"), atomically: true, encoding: .utf8)
    }

    public var commonName: String {
        for rdn in certificate.subject { for a in rdn where a.type == .RDNAttributeType.commonName {
            if let s = String(a.value) { return s }
        } }
        return ""
    }

    /// 리프·캐시 키용 호스트: 소문자, 끝 점 제거, IPv6 대괄호 제거.
    static func normalizedHost(_ rawHost: String) -> String {
        var host = rawHost.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host
    }

    /// 호출마다 새로 발급한다(캐시는 `ProxyServer.leafContexts`가 호스트당 하나).
    public func leaf(for rawHost: String) throws -> LeafCertificate {
        let host = Self.normalizedHost(rawHost)
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
        return LeafCertificate(certificateDER: s.serializedBytes, privateKeyDER: Array(leafKey.derRepresentation))
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
