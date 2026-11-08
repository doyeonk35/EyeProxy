import Foundation

/// Proxyman `NetworkThrottlingService`의 `networkProfile`. 대역폭은 B/s 상한, 지연은 ms, 손실은 %.
/// EyeProxy 전용 하한은 `eyeproxy` 하위 객체에 둔다(없으면 상한의 50%).
public struct NetworkProfile: Codable, Equatable, Sendable {
    public var name: String
    public var profileType: Int
    public var downloadBandwidth: Int
    public var uploadBandwidth: Int
    public var downloadBandwidthTitle: String
    public var uploadBandwidthTitle: String
    public var delay: Int
    public var minimumWaitTime: Int
    public var packageDrop: Double
    public var isAllLostConnection: Bool
    public var downloadMin: Int?
    public var uploadMin: Int?

    public init(name: String, profileType: Int = 1, downloadBandwidth: Int, uploadBandwidth: Int,
                downloadBandwidthTitle: String = "", uploadBandwidthTitle: String = "", delay: Int = 0,
                minimumWaitTime: Int = 0, packageDrop: Double = 0, isAllLostConnection: Bool = false,
                downloadMin: Int? = nil, uploadMin: Int? = nil) {
        self.name = name
        self.profileType = profileType
        self.downloadBandwidth = downloadBandwidth
        self.uploadBandwidth = uploadBandwidth
        self.downloadBandwidthTitle = downloadBandwidthTitle
        self.uploadBandwidthTitle = uploadBandwidthTitle
        self.delay = delay
        self.minimumWaitTime = minimumWaitTime
        self.packageDrop = packageDrop
        self.isAllLostConnection = isAllLostConnection
        self.downloadMin = downloadMin
        self.uploadMin = uploadMin
    }

    private enum CodingKeys: String, CodingKey {
        case name, profileType, downloadBandwidth, uploadBandwidth, downloadBandwidthTitle, uploadBandwidthTitle
        case delay, minimumWaitTime, packageDrop, isAllLostConnection, eyeproxy
    }
    private enum Extra: String, CodingKey { case downloadMin, uploadMin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        profileType = try c.decodeIfPresent(Int.self, forKey: .profileType) ?? 1
        downloadBandwidth = try c.decode(Int.self, forKey: .downloadBandwidth)
        uploadBandwidth = try c.decode(Int.self, forKey: .uploadBandwidth)
        downloadBandwidthTitle = try c.decodeIfPresent(String.self, forKey: .downloadBandwidthTitle) ?? ""
        uploadBandwidthTitle = try c.decodeIfPresent(String.self, forKey: .uploadBandwidthTitle) ?? ""
        delay = try c.decodeIfPresent(Int.self, forKey: .delay) ?? 0
        minimumWaitTime = try c.decodeIfPresent(Int.self, forKey: .minimumWaitTime) ?? 0
        packageDrop = try c.decodeIfPresent(Double.self, forKey: .packageDrop) ?? 0
        isAllLostConnection = try c.decodeIfPresent(Bool.self, forKey: .isAllLostConnection) ?? false
        if let e = try? c.nestedContainer(keyedBy: Extra.self, forKey: .eyeproxy) {
            downloadMin = try e.decodeIfPresent(Int.self, forKey: .downloadMin)
            uploadMin = try e.decodeIfPresent(Int.self, forKey: .uploadMin)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(profileType, forKey: .profileType)
        try c.encode(downloadBandwidth, forKey: .downloadBandwidth)
        try c.encode(uploadBandwidth, forKey: .uploadBandwidth)
        try c.encode(downloadBandwidthTitle, forKey: .downloadBandwidthTitle)
        try c.encode(uploadBandwidthTitle, forKey: .uploadBandwidthTitle)
        try c.encode(delay, forKey: .delay)
        try c.encode(minimumWaitTime, forKey: .minimumWaitTime)
        try c.encode(packageDrop, forKey: .packageDrop)
        try c.encode(isAllLostConnection, forKey: .isAllLostConnection)
        if downloadMin != nil || uploadMin != nil {
            var e = c.nestedContainer(keyedBy: Extra.self, forKey: .eyeproxy)
            try e.encodeIfPresent(downloadMin, forKey: .downloadMin)
            try e.encodeIfPresent(uploadMin, forKey: .uploadMin)
        }
    }

    // MARK: 프리셋 (§5.7). 지연·손실은 [내 판단] 표.

    private static let mbps = 125_000, kbps = 125

    /// `lo`가 nil이면 "< hi" 표기: 하한은 상한의 50%.
    private static func preset(_ name: String, down: (Int?, Int), up: (Int?, Int), unit: Int, titles: (String, String),
                               delay: Int, drop: Double) -> NetworkProfile {
        NetworkProfile(name: name, profileType: 0, downloadBandwidth: down.1 * unit, uploadBandwidth: up.1 * unit,
                       downloadBandwidthTitle: titles.0, uploadBandwidthTitle: titles.1, delay: delay, packageDrop: drop,
                       downloadMin: (down.0 ?? down.1 / 2) * unit, uploadMin: (up.0 ?? up.1 / 2) * unit)
    }

    public static let presets: [NetworkProfile] = {
        var loss = NetworkProfile(name: "100% Loss", profileType: 0, downloadBandwidth: 0, uploadBandwidth: 0,
                                  packageDrop: 100, isAllLostConnection: true, downloadMin: 0, uploadMin: 0)
        loss.downloadBandwidthTitle = "0"; loss.uploadBandwidthTitle = "0"
        return [
            loss,
            // "<1 mbps"는 정수로 못 나누므로 kbps 단위(1 mbps = 1000 kbps)로 계산한다.
            preset("Very Bad Network", down: (500, 1000), up: (500, 1000), unit: kbps, titles: ("<1 mbps", "<1 mbps"), delay: 1400, drop: 10),
            preset("Slow Network", down: (5, 10), up: (5, 10), unit: mbps, titles: ("5-10 mbps", "5-10 mbps"), delay: 150, drop: 1),
            preset("Medium Network", down: (10, 20), up: (10, 20), unit: mbps, titles: ("10-20 mbps", "10-20 mbps"), delay: 80, drop: 0.5),
            preset("2G (EDGE)", down: (nil, 240), up: (nil, 200), unit: kbps, titles: ("<240 kbps", "<200 kbps"), delay: 650, drop: 5),
            preset("3G", down: (nil, 780), up: (nil, 330), unit: kbps, titles: ("<780 kbps", "<330 kbps"), delay: 200, drop: 2),
            preset("4G (LTE)", down: (30, 50), up: (5, 10), unit: mbps, titles: ("30-50 mbps", "5-10 mbps"), delay: 50, drop: 0),
            preset("5G", down: (50, 150), up: (10, 50), unit: mbps, titles: ("50-150 mbps", "10-50 mbps"), delay: 20, drop: 0),
            preset("Wi-Fi", down: (25, 40), up: (15, 30), unit: mbps, titles: ("25-40 mbps", "15-30 mbps"), delay: 10, drop: 0),
            preset("Wi-Fi 802.11ac", down: (150, 250), up: (70, 100), unit: mbps, titles: ("150-250 mbps", "70-100 mbps"), delay: 5, drop: 0),
        ]
    }()
}
