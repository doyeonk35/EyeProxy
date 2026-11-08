import Foundation
import EyeProxyCore

/// 인증서 내보내기 실패.
public enum CertificateExportError: Error {
    /// openssl이 0이 아닌 코드로 끝남(stderr).
    case openSSL(String)
    /// /usr/bin/openssl을 실행할 수 없음.
    case openSSLMissing
}

/// CA 인증서·개인키를 PEM·DER·P12 파일로 내보낸다.
public enum CertificateExporter {
    static let openSSL = "/usr/bin/openssl"

    /// CA 인증서를 PEM으로 쓴다.
    public static func writePEM(_ ca: CertificateAuthority, to url: URL) throws {
        try Data(ca.certificatePEM.utf8).write(to: url, options: .atomic)
    }

    /// CA 인증서를 DER로 쓴다.
    public static func writeDER(_ ca: CertificateAuthority, to url: URL) throws {
        try Data(ca.certificateDER).write(to: url, options: .atomic)
    }

    /// 0600으로 생성. 기존 파일은 지우고 새로 만든다.
    public static func writePrivateKey(_ ca: CertificateAuthority, to url: URL) throws {
        try createSecret(Data(ca.privateKeyPEM.utf8), at: url)
    }

    /// /usr/bin/openssl pkcs12 -export. 비밀번호는 환경 변수 P12PASS로만 전달(-passout env:P12PASS). 빈 비밀번호 허용.
    public static func writeP12(_ ca: CertificateAuthority, to url: URL, password: String) async throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: openSSL) else { throw CertificateExportError.openSSLMissing }
        let dir = fm.temporaryDirectory.appending(path: "eyeproxy-p12-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let keyURL = dir.appending(path: "key.pem"), certURL = dir.appending(path: "cert.pem"), outURL = dir.appending(path: "out.p12")
        try createSecret(Data(ca.privateKeyPEM.utf8), at: keyURL)
        try Data(ca.certificatePEM.utf8).write(to: certURL)
        let r = try await Shell.run(openSSL, ["pkcs12", "-export", "-inkey", keyURL.path, "-in", certURL.path, "-name", ca.commonName,
                                              "-out", outURL.path, "-passout", "env:P12PASS"],
                                    environment: ["P12PASS": password])
        guard r.status == 0 else { throw CertificateExportError.openSSL(r.stderr) }
        // 0700 임시 폴더 안에서 0600으로 맞춘 뒤 옮겨, 목적지에 넓은 권한으로 노출되는 순간이 없게 한다.
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outURL.path)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: outURL, to: url)
    }

    /// 기존 파일을 지우고 처음부터 0600으로 만든다(권한이 생성 시점에 정해지도록).
    private static func createSecret(_ data: Data, at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
