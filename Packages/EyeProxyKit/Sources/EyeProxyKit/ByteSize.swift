import Foundation

/// 크기 표시. 앱 언어와 무관하게 영어 파일 단위(1000 단위, 소수 한 자리): "198 bytes", "2.9 KB", "1.2 MB".
/// (`ByteCountFormatter`·`.byteCount`는 로캘을 따라 "바이트"/"kB"가 되거나 KB에서 소수를 버린다.)
public enum ByteSize {
    public static func format(_ count: Int) -> String {
        guard count >= 1000 else { return count == 1 ? "1 byte" : "\(count) bytes" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(count) / 1000, unit = 0
        while value >= 999.95, unit < units.count - 1 { value /= 1000; unit += 1 }
        return value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            + " " + units[unit]
    }
}
