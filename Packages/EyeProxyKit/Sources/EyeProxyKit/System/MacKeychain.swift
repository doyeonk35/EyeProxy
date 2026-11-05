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

    public static func isInstalled(commonName: String) async -> Bool {
        (try? await Shell.run("/usr/bin/security", ["find-certificate", "-c", commonName, loginKeychain]).status) == 0
    }
}
