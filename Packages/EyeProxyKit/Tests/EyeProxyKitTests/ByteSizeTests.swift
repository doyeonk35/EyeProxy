import Testing
@testable import EyeProxyKit

@Test func byteSizeIsEnglishFileUnits() {
    #expect(ByteSize.format(0) == "0 bytes")
    #expect(ByteSize.format(198) == "198 bytes")
    #expect(ByteSize.format(2_900) == "2.9 KB")
    #expect(ByteSize.format(1_200_000) == "1.2 MB")
    #expect(ByteSize.format(999_960) == "1 MB" && ByteSize.format(3_000) == "3 KB")
}
