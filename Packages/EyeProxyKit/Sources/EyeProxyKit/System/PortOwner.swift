import Foundation

/// TCP 포트를 LISTEN 중인 프로세스 조회(읽기 전용 lsof).
public enum PortOwner {
    public static func listeners(onPort port: Int) async -> [(name: String, pid: Int32)] {
        guard let r = try? await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "pcn"]) else { return [] }
        return parseLsofFields(r.stdout)
    }

    /// `-F pcn` 출력: `p<pid>` 다음에 `c<command>`, 소켓마다 `n<name>`. pid 기준 중복 제거.
    static func parseLsofFields(_ output: String) -> [(name: String, pid: Int32)] {
        var result: [(name: String, pid: Int32)] = []
        var pid: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p": pid = Int32(value)
            case "c":
                if let pid, !result.contains(where: { $0.pid == pid }) { result.append((String(value), pid)) }
            default: break
            }
        }
        return result
    }
}
