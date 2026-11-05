import Foundation

enum ShellError: Error { case privilegedFailed(String) }

/// 절대경로 실행 파일을 Process로 실행. 0이 아닌 종료 코드는 throw하지 않는다(호출자가 status 확인).
/// stdin: 표준 입력으로 줄 문자열(scutil 대화형 명령 등). 출력과 같이 임시 파일로 넘긴다.
enum Shell {
    static func run(_ command: String, _ args: [String], stdin: String? = nil) async throws -> (status: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: command)
            p.arguments = args
            // 파이프 버퍼(64KB) 교착을 피하려고 임시 파일로 출력을 받는다.
            let dir = FileManager.default.temporaryDirectory
            let outURL = dir.appending(path: "eyeproxy-\(UUID()).out"), errURL = dir.appending(path: "eyeproxy-\(UUID()).err")
            let inURL = dir.appending(path: "eyeproxy-\(UUID()).in")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            FileManager.default.createFile(atPath: inURL.path, contents: Data((stdin ?? "").utf8))
            let outHandle = try? FileHandle(forWritingTo: outURL), errHandle = try? FileHandle(forWritingTo: errURL)
            let inHandle = stdin == nil ? nil : try? FileHandle(forReadingFrom: inURL)
            var started = false
            // 시작하지 못하면(핸들 실패·run() throw) terminationHandler가 불리지 않으므로 여기서 정리한다.
            defer {
                if !started {
                    try? outHandle?.close(); try? errHandle?.close(); try? inHandle?.close()
                    try? FileManager.default.removeItem(at: outURL); try? FileManager.default.removeItem(at: errURL)
                    try? FileManager.default.removeItem(at: inURL)
                }
            }
            guard let out = outHandle, let err = errHandle, stdin == nil || inHandle != nil else {
                cont.resume(throwing: ShellError.privilegedFailed("temp file")); return
            }
            p.standardOutput = out; p.standardError = err
            if let inHandle { p.standardInput = inHandle }
            p.terminationHandler = { proc in
                try? out.close(); try? err.close(); try? inHandle?.close()
                try? FileManager.default.removeItem(at: inURL)
                let o = String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self)
                let e = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
                try? FileManager.default.removeItem(at: outURL); try? FileManager.default.removeItem(at: errURL)
                cont.resume(returning: (proc.terminationStatus, o, e))
            }
            do { try p.run(); started = true } catch { cont.resume(throwing: error) }
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
