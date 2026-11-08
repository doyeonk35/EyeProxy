import Foundation
import EyeProxyCore

/// 루트 CA 초기화: 기존 CA 폴더를 형제 백업 폴더로 옮기고(지우지 않음) 새 CA를 만든다.
public enum CARotation {
    /// directory(…/ca)를 `ca-backup-<yyyyMMdd-HHmmss>[-n]`(형제 폴더)로 옮기고 새 CA를 생성·저장해 돌려준다. directory가 없으면 백업 없이 생성만.
    public static func rotate(directory: URL, commonName: String, now: Date = .now) throws -> (ca: CertificateAuthority, backup: URL?) {
        let fm = FileManager.default
        // 생성이 실패하면 기존 CA를 건드리지 않는다.
        let ca = try CertificateAuthority.generate(commonName: commonName)
        var backup: URL?
        if fm.fileExists(atPath: directory.path) {
            let target = backupURL(for: directory, now: now)
            try fm.moveItem(at: directory, to: target)
            backup = target
        }
        do {
            try ca.save(to: directory)
        } catch {
            // 저장 실패: 반쯤 만든 폴더를 치우고 옛 CA를 제자리로 되돌린다.
            if let backup {
                try? fm.removeItem(at: directory)
                try? fm.moveItem(at: backup, to: directory)
            }
            throw error
        }
        return (ca, backup)
    }

    /// 같은 초에 겹치면 `-2`, `-3`… 을 붙인다.
    static func backupURL(for directory: URL, now: Date) -> URL {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let parent = directory.deletingLastPathComponent()
        let base = "ca-backup-\(stamp.string(from: now))"
        var candidate = parent.appending(path: base)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appending(path: "\(base)-\(n)")
            n += 1
        }
        return candidate
    }
}
