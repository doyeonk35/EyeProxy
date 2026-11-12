import Testing
@testable import EyeProxyKit

@Test func parsesAirPlayName() {
    let r = DeviceDiscovery.parse(serviceType: "_airplay._tcp", serviceName: "거실 Apple TV", txt: ["model": "AppleTV14,1"])
    #expect(r?.name == "거실 Apple TV"); #expect(r?.kind == .appleTV)
}
@Test func parsesCompanionLinkKind() {
    #expect(DeviceDiscovery.parse(serviceType: "_companion-link._tcp", serviceName: "테스트 iPhone", txt: ["rpMd": "iPhone15,2"])?.kind == .iPhone)
}
@Test func parsesGoogleCastFriendlyName() {
    let r = DeviceDiscovery.parse(serviceType: "_googlecast._tcp", serviceName: "Google-TV-0000", txt: ["fn": "안방 TV", "md": "Chromecast"])
    #expect(r?.name == "안방 TV"); #expect(r?.kind == .googleTV)
}
@Test func googleCastWithoutFriendlyNameIsIgnored() {
    #expect(DeviceDiscovery.parse(serviceType: "_googlecast._tcp", serviceName: "Google-TV-0000", txt: [:]) == nil)
}
@Test func normalizesMappedIPv4() { #expect(DeviceDiscovery.normalize("::ffff:192.0.2.10") == "192.0.2.10") }
@Test func txtOnlyChangeDoesNotResolveAgain() {
    let type = "_companion-link._tcp"
    let old = (name: "테스트 iPhone", txt: ["rpMd": "iPhone15,2", "rpBA": "00:00:00:00:00:01"])
    #expect(!DeviceDiscovery.needsResolve(serviceType: type, old: old, new: (old.name, ["rpMd": "iPhone15,2", "rpBA": "00:00:00:00:00:02"])))
    #expect(DeviceDiscovery.needsResolve(serviceType: type, old: old, new: ("거실 iPhone", old.txt)))
    #expect(DeviceDiscovery.needsResolve(serviceType: type, old: old, new: (old.name, ["rpMd": "iPad14,1"])))
}

@Test func castModelMapsToAndroidKinds() {
    #expect(DeviceDiscovery.castKind(model: "Google TV Streamer") == .googleTV)
    #expect(DeviceDiscovery.castKind(model: "Chromecast") == .googleTV)
    #expect(DeviceDiscovery.castKind(model: "SHIELD Android TV") == .androidTV)
    #expect(DeviceDiscovery.castKind(model: "BRAVIA 4K VH2") == .androidTV)
    #expect(DeviceDiscovery.castKind(model: "Google Nest Mini") == nil)
    #expect(DeviceDiscovery.castKind(model: "Google Home") == nil)
    #expect(DeviceDiscovery.castKind(model: "Nest Hub") == nil)
    #expect(DeviceDiscovery.castKind(model: nil) == nil)
}
