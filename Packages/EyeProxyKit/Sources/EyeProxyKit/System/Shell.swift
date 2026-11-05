import Foundation

enum ShellError: Error { case privilegedFailed(String) }

/// 절대경로 실행 파일을 Process로 실행. 0이 아닌 종료 코드는 throw하지 않는다(호출자가 status 확인).
enum Shell {
    static func run(_ command: String, _ args: [String]) async throws -> (status: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: command)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            // ponytail: 파이프를 종료 후 읽음 — 64KB 초과 출력 시 교착 가능. 이 CLI들은 출력이 작다.
            p.terminationHandler = { proc in
                let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: (proc.terminationStatus, o, e))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

/// osascript `do shell script … with administrator privileges`
enum PrivilegedShell {
    static func run(_ script: String) async throws -> String {
        let esc = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let r = try await Shell.run("/usr/bin/osascript", ["-e", "do shell script \"\(esc)\" with administrator privileges"])
        guard r.status == 0 else { throw ShellError.privilegedFailed(r.stderr) }
        return r.stdout
    }
}
