import Foundation

public enum MacKeychainError: Error { case installFailed(String) }

public enum MacKeychain {
    private static var loginKeychain: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Keychains/login.keychain-db").path
    }

    public static func installTrustedRoot(pemURL: URL) async throws {
        let r = try await Shell.run("/usr/bin/security", ["add-trusted-cert", "-r", "trustRoot", "-k", loginKeychain, pemURL.path])
        guard r.status == 0 else { throw MacKeychainError.installFailed(r.stderr) }
    }

    /// `security find-certificate -a -Z` 출력의 `SHA-256 hash:` 값들 (대문자 hex, 콜론 없음).
    public static func fingerprints(fromFindCertificateOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("SHA-256 hash:") else { return nil }
            return line.dropFirst("SHA-256 hash:".count).trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    /// 로그인 키체인에 해당 PEM과 SHA-256 지문이 같은 인증서가 있는지.
    public static func isInstalled(pemURL: URL) async -> Bool {
        guard let fp = try? await Shell.run("/usr/bin/openssl", ["x509", "-noout", "-fingerprint", "-sha256", "-in", pemURL.path]),
              fp.status == 0, let eq = fp.stdout.firstIndex(of: "=") else { return false }
        let want = fp.stdout[fp.stdout.index(after: eq)...].filter { $0 != ":" && !$0.isWhitespace }.uppercased()
        guard let all = try? await Shell.run("/usr/bin/security", ["find-certificate", "-a", "-Z", loginKeychain]), all.status == 0 else { return false }
        return fingerprints(fromFindCertificateOutput: all.stdout).contains(want)
    }
}
