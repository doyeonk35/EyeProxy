import Testing
@testable import EyeProxyKit

@Test func parsesFindCertificateFingerprints() {
    let out = """
    keychain: "/Users/x/Library/Keychains/login.keychain-db"
    SHA-256 hash: ab12CD
    SHA-1 hash: 0011
    attributes:
        "labl"<blob>="EyeProxy CA"
    SHA-256 hash: EF34
    """
    #expect(MacKeychain.fingerprints(fromFindCertificateOutput: out) == ["AB12CD", "EF34"])
}
