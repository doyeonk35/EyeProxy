import EyeProxyCore
import Foundation
import Observation

public enum FlowLayout: String, Codable, Sendable { case classic, sideBySide }

@Observable @MainActor
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var port: Int { didSet { defaults.set(port, forKey: "eyeproxy.port") } }
    public var sslEnabled: Bool { didSet { defaults.set(sslEnabled, forKey: "eyeproxy.sslEnabled") } }
    public var sslPatterns: [String] { didSet { defaults.set(sslPatterns, forKey: "eyeproxy.sslPatterns") } }
    public var bypassHosts: [String] { didSet { defaults.set(bypassHosts, forKey: "eyeproxy.bypassHosts") } }
    public var layout: FlowLayout { didSet { defaults.set(layout.rawValue, forKey: "eyeproxy.layout") } }
    /// 저장하지 않는다 (실행할 때마다 기록 중으로 시작).
    public var isRecording = true

    public var sslPolicy: SSLProxyingPolicy { SSLProxyingPolicy(isEnabled: sslEnabled, patterns: sslPatterns) }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        port = defaults.object(forKey: "eyeproxy.port") as? Int ?? 9090
        sslEnabled = defaults.object(forKey: "eyeproxy.sslEnabled") as? Bool ?? true
        sslPatterns = defaults.stringArray(forKey: "eyeproxy.sslPatterns") ?? []
        bypassHosts = defaults.stringArray(forKey: "eyeproxy.bypassHosts") ?? ["localhost", "127.0.0.1", "*.local"]
        layout = defaults.string(forKey: "eyeproxy.layout").flatMap(FlowLayout.init(rawValue:)) ?? .classic
    }
}
