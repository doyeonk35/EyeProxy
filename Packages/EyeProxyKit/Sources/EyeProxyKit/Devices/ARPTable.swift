import Darwin

/// ARP 표(`arp -a`와 같은 표)에서 IPv4 주소의 MAC을 읽는다. 외부 도구·권한 없이 sysctl만 쓴다(스펙 §4.3.1).
public enum ARPTable {
    /// sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO)로 표를 읽어 그 IPv4의 MAC. 실패·없음이면 nil.
    public static func macAddress(for ipv4: String) -> String? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        size += size / 2  // 두 번 부르는 사이에 표가 늘어도 ENOMEM이 나지 않게
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))[ipv4]
    }

    /// 라우팅 메시지 버퍼 → [IPv4: MAC]. arp.c와 같은 방식: rt_msghdr 뒤에 sockaddr_in, 그다음(4바이트 올림) sockaddr_dl.
    /// 짧거나 어긋난 버퍼는 그 메시지(또는 나머지)를 버린다.
    static func parse(_ buffer: [UInt8]) -> [String: String] {
        let headerSize = MemoryLayout<rt_msghdr>.size
        let sinSize = MemoryLayout<sockaddr_in>.size
        let sinAddr = MemoryLayout<sockaddr_in>.offset(of: \.sin_addr)!
        let sdlNameLength = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_nlen)!
        let sdlAddressLength = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_alen)!
        let sdlData = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!
        var table: [String: String] = [:]
        var start = 0
        while start + 2 <= buffer.count {
            // rtm_msglen(u_short, 호스트 바이트 순서)은 메시지 맨 앞이다.
            let length = Int(buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: start, as: UInt16.self) })
            guard length > 0, start + length <= buffer.count else { break }
            let end = start + length
            defer { start = end }
            let sin = start + headerSize
            guard sin + sinSize <= end, Int32(buffer[sin + 1]) == AF_INET else { continue }
            let sinLength = Int(buffer[sin])
            let sdl = sin + (sinLength > 0 ? 1 + ((sinLength - 1) | 3) : 4)
            guard sdl + sdlData <= end, Int32(buffer[sdl + 1]) == AF_LINK else { continue }
            let macStart = sdl + sdlData + Int(buffer[sdl + sdlNameLength])
            let macEnd = macStart + Int(buffer[sdl + sdlAddressLength])
            guard macEnd <= min(end, sdl + Int(buffer[sdl])), let mac = format(Array(buffer[macStart..<macEnd])) else { continue }
            let ip = buffer[(sin + sinAddr)..<(sin + sinAddr + 4)].map(String.init).joined(separator: ".")
            table[ip] = mac
        }
        return table
    }

    /// 6바이트가 아니거나 모두 0, 모두 0xff면 nil. 소문자 두 자리, ":" 구분.
    static func format(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes.contains(where: { $0 != 0xff }) else { return nil }
        return bytes.map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined(separator: ":")
    }
}
