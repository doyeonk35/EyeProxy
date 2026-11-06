import Foundation

/// 헬퍼 프로세스(예: com.apple.WebKit.Networking)의 책임 앱 pid. 비공개 함수라 dlsym으로 찾고, 없으면 입력 그대로.
enum ResponsiblePID {
    private typealias Fn = @convention(c) (pid_t) -> pid_t
    private static let fn: Fn? = {
        // RTLD_DEFAULT = (void *)-2
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(p, to: Fn.self)
    }()

    static func lookup(_ pid: Int32) -> Int32 {
        guard let r = fn?(pid), r > 0 else { return pid }
        return r
    }
}
