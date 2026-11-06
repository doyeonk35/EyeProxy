import Testing
@testable import EyeProxyKit

@Test func identityDerivesNameAndSimulatorFromPath() {
    let sim = ProcessIdentity(pid: 10, path: "/Users/me/Library/Developer/CoreSimulator/Devices/ABCD-1234/data/Containers/Bundle/Application/X/TVING.app/TVING")
    #expect(sim.name == "TVING" && sim.simulator == SimulatorRef(udid: "ABCD-1234", appName: "TVING") && sim.groupKey == "sim:ABCD-1234:TVING")
    #expect(sim.displayName(runtimes: ["ABCD-1234": "tvOS 18.1"]) == "TVING (tvOS 시뮬레이터)" && sim.displayName(runtimes: [:]) == "TVING (시뮬레이터)")
    let safari = ProcessIdentity(pid: 11, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    #expect(safari.name == "Safari" && safari.simulator == nil && safari.groupKey == "/Applications/Safari.app/Contents/MacOS/Safari" && safari.displayName(runtimes: [:]) == "Safari")
    let daemon = ProcessIdentity(pid: 12, path: "/usr/libexec/nsurlsessiond"); #expect(daemon.name == "nsurlsessiond")
    #expect(ProcessIdentity(pid: 13, path: nil).name == "pid 13")
}
