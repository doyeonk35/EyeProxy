import Darwin

extension AppModel {
    private static let virtualInterfacePrefixes = ["utun", "bridge", "awdl", "llw"]

    /// 켜진 물리 인터페이스의 IPv4 주소(루프백·링크로컬·VPN·브리지·AWDL 제외). 기기 프록시 설정에 쓸 주소.
    var lanAddresses: [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        return sequence(first: first) { $0.pointee.ifa_next }.compactMap { p -> String? in
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  p.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  !Self.virtualInterfacePrefixes.contains(where: String(cString: p.pointee.ifa_name).hasPrefix) else { return nil }
            let sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let ip = String(cString: inet_ntoa(sin.sin_addr))
            return ip.hasPrefix("127.") || ip.hasPrefix("169.254.") ? nil : ip
        }
    }
}
