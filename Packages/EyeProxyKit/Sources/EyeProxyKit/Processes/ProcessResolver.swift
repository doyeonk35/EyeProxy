import Foundation

public enum ProcessLookup {
    /// `lsof -nP -iTCP:<proxyPort> -F pcn` 출력 → [클라이언트 로컬 포트: pid]. 목적지 포트가 proxyPort인 연결만 채택한다.
    static func parseLsof(_ output: String, proxyPort: Int, excludingPID: Int32) -> [Int: Int32] {
        var result: [Int: Int32] = [:]
        var pid: Int32?
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p": pid = Int32(value)
            case "n":
                guard let pid, pid != excludingPID else { continue }
                let ends = value.components(separatedBy: "->")
                guard ends.count == 2, port(of: ends[1]) == proxyPort, let local = port(of: ends[0]) else { continue }
                result[local] = pid
            default: continue   // f(fd)·c(command) 등
            }
        }
        return result
    }

    private static func port(of endpoint: String) -> Int? {
        endpoint.lastIndex(of: ":").flatMap { Int(endpoint[endpoint.index(after: $0)...]) }
    }
}

/// 클라이언트 로컬 포트 → 소켓을 연 프로세스(헬퍼면 책임 앱). 100ms 디바운스로 lsof 한 번에 여러 포트를 묶는다.
public actor ProcessResolver {
    private var cache: [Int: ProcessIdentity] = [:]
    private var pending: Set<Int> = []
    private var batch: Task<Void, Never>?

    public init() {}

    public func resolve(port: Int, proxyPort: Int) async -> ProcessIdentity? {
        if let hit = cache[port] { return hit }
        await enqueue(port, proxyPort)
        if let hit = cache[port] { return hit }
        // 소켓이 막 열려 lsof에 아직 안 보일 수 있다: 한 번만 재시도.
        try? await Task.sleep(for: .milliseconds(300))
        await enqueue(port, proxyPort)
        return cache[port]
    }

    // ponytail: 배치는 첫 요청의 proxyPort를 쓴다. 프록시 포트가 동시에 둘 이상 필요해지면 pending을 포트별로 나눈다.
    private func enqueue(_ port: Int, _ proxyPort: Int) async {
        pending.insert(port)
        let task = batch ?? Task { [self] in
            try? await Task.sleep(for: .milliseconds(100))
            await runBatch(proxyPort)
        }
        batch = task
        await task.value
    }

    private func runBatch(_ proxyPort: Int) async {
        let ports = pending
        pending = []
        batch = nil
        guard let r = try? await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(proxyPort)", "-F", "pcn"]) else { return }
        let found = ProcessLookup.parseLsof(r.stdout, proxyPort: proxyPort, excludingPID: ProcessInfo.processInfo.processIdentifier)
        for (port, pid) in found where ports.contains(port) {
            let owner = ResponsiblePID.lookup(pid)
            cache[port] = ProcessIdentity(pid: owner, path: Self.path(of: owner))
        }
    }

    private static func path(of pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }
}
