import Testing
import Foundation
import EyeProxyCore
@testable import EyeProxyKit

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func pemAndDerExportsMatchCA() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let ca = try CertificateAuthority.generate()
    let pem = dir.appending(path: "ca.pem"), der = dir.appending(path: "ca.cer")
    try CertificateExporter.writePEM(ca, to: pem)
    try CertificateExporter.writeDER(ca, to: der)
    #expect(try Data(contentsOf: pem) == Data(ca.certificatePEM.utf8))
    #expect(try Data(contentsOf: der) == Data(ca.certificateDER))
}

@Test func privateKeyExportOverwritesWithMode600() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let ca = try CertificateAuthority.generate()
    let url = dir.appending(path: "key.pem")
    #expect(FileManager.default.createFile(atPath: url.path, contents: Data("old".utf8), attributes: [.posixPermissions: 0o644]))
    try CertificateExporter.writePrivateKey(ca, to: url)
    #expect(try Data(contentsOf: url) == Data(ca.privateKeyPEM.utf8))
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func p12ExportIsReadableByOpenSSL() async throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let ca = try CertificateAuthority.generate()
    for password in ["pw", ""] {
        let url = dir.appending(path: "ca-\(password.count).p12")
        try await CertificateExporter.writeP12(ca, to: url, password: password)
        let r = try await Shell.run("/usr/bin/openssl", ["pkcs12", "-in", url.path, "-info", "-nokeys", "-passin", "env:P12PASS"],
                                    environment: ["P12PASS": password])
        #expect(r.status == 0)
        #expect(r.stdout.contains("BEGIN CERTIFICATE"))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
