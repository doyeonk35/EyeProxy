import Testing
import Foundation
import EyeProxyCore
@testable import EyeProxyKit

/// 임시 부모 폴더 아래의 `ca` 경로(아직 만들지 않음). 백업이 형제로 생기므로 부모째 지운다.
private func caDirInTempParent() -> (parent: URL, dir: URL) {
    let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return (parent, parent.appending(path: "ca"))
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

@Test func rotateMovesOldAndCreatesNew() throws {
    let (parent, dir) = caDirInTempParent(); defer { try? FileManager.default.removeItem(at: parent) }
    let old = try CertificateAuthority.generate()
    try old.save(to: dir)
    let (ca, backup) = try CARotation.rotate(directory: dir, commonName: "Rotated CA")
    let b = try #require(backup)
    #expect(b.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL)
    #expect(b.lastPathComponent.hasPrefix("ca-backup-"))
    #expect(exists(b.appending(path: "ca.pem")) && exists(b.appending(path: "ca-key.pem")))
    #expect(try CertificateAuthority.load(from: b)?.certificateDER == old.certificateDER)
    #expect(exists(dir.appending(path: "ca.pem")))
    let loaded = try #require(try CertificateAuthority.load(from: dir))
    #expect(loaded.certificateDER != old.certificateDER)
    #expect(loaded.certificateDER == ca.certificateDER)
    #expect(ca.commonName == "Rotated CA")
}

@Test func rotateWithoutExistingDirectoryJustCreates() throws {
    let (parent, dir) = caDirInTempParent(); defer { try? FileManager.default.removeItem(at: parent) }
    let (ca, backup) = try CARotation.rotate(directory: dir, commonName: "Fresh CA")
    #expect(backup == nil)
    #expect(try CertificateAuthority.load(from: dir)?.certificateDER == ca.certificateDER)
    #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["ca"])
}

@Test func rotateTwiceInSameSecondKeepsBothBackups() throws {
    let (parent, dir) = caDirInTempParent(); defer { try? FileManager.default.removeItem(at: parent) }
    try CertificateAuthority.generate().save(to: dir)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let first = try #require(try CARotation.rotate(directory: dir, commonName: "A", now: now).backup)
    let second = try #require(try CARotation.rotate(directory: dir, commonName: "B", now: now).backup)
    let stamp = DateFormatter()
    stamp.locale = Locale(identifier: "en_US_POSIX")
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    let base = "ca-backup-\(stamp.string(from: now))"
    #expect(first.lastPathComponent == base)
    #expect(second.lastPathComponent == base + "-2")
    #expect(exists(first.appending(path: "ca.pem")) && exists(second.appending(path: "ca.pem")))
}
