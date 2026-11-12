import Darwin
import Testing
@testable import EyeProxyKit

@Test func formatsMAC() {
    #expect(ARPTable.format([0x00, 0x00, 0x5e, 0x00, 0x53, 0x01]) == "00:00:5e:00:53:01")
    #expect(ARPTable.format([UInt8](repeating: 0, count: 6)) == nil)
    #expect(ARPTable.format([UInt8](repeating: 0xff, count: 6)) == nil)
    #expect(ARPTable.format([0x00, 0x00, 0x5e, 0x00, 0x53]) == nil)
}

/// rt_msghdr + sockaddr_in + sockaddr_dl(arp.c가 읽는 모양).
private func routeMessage(ip: [UInt8], mac: [UInt8]) -> [UInt8] {
    let sin: [UInt8] = [16, UInt8(AF_INET), 0, 0] + ip + [UInt8](repeating: 0, count: 8)
    let sdl: [UInt8] = [20, UInt8(AF_LINK), 0, 0, 0, 0, UInt8(mac.count), 0] + mac + [UInt8](repeating: 0, count: 12 - mac.count)
    var header = rt_msghdr()
    header.rtm_msglen = UInt16(MemoryLayout<rt_msghdr>.size + sin.count + sdl.count)
    return withUnsafeBytes(of: &header) { Array($0) } + sin + sdl
}

@Test func parsesRouteMessage() {
    let complete = routeMessage(ip: [192, 0, 2, 20], mac: [0x00, 0x00, 0x5e, 0x00, 0x53, 0x14])
    let incomplete = routeMessage(ip: [192, 0, 2, 21], mac: [])
    #expect(ARPTable.parse(complete + incomplete) == ["192.0.2.20": "00:00:5e:00:53:14"])
}

@Test func parseSkipsMalformedBuffers() {
    let good = routeMessage(ip: [192, 0, 2, 20], mac: [0x00, 0x00, 0x5e, 0x00, 0x53, 0x14])
    #expect(ARPTable.parse([]).isEmpty)
    #expect(ARPTable.parse([0x01]).isEmpty)
    // 잘린 메시지, rtm_msglen 0(무한 반복 방지), 헤더보다 짧은 msglen
    for cut in [2, MemoryLayout<rt_msghdr>.size, good.count - 1] {
        #expect(ARPTable.parse(Array(good.prefix(cut))).isEmpty)
    }
    #expect(ARPTable.parse([0, 0] + good).isEmpty)
    var short = good
    short[0] = 4; short[1] = 0
    #expect(ARPTable.parse(short).isEmpty)
    // sdl_len·sdl_nlen이 메시지 밖을 가리키면 버린다
    var badNameLength = good
    badNameLength[MemoryLayout<rt_msghdr>.size + 16 + 5] = 200
    #expect(ARPTable.parse(badNameLength).isEmpty)
}

/// 실제 표를 읽어도 죽지 않는지만 본다(결과는 환경마다 다르다).
@Test func liveTableLookupDoesNotCrash() {
    _ = ARPTable.macAddress(for: "192.0.2.1")
}
