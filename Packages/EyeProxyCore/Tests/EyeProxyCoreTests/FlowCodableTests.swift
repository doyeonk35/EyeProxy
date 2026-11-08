import Foundation
import Testing
@testable import EyeProxyCore

struct FlowCodableTests {
    @Test func decodesFlowWithoutClientPort() throws {
        let json = #"{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"clientAddress":"127.0.0.1","startedAt":0,"request":{"method":"GET","scheme":"https","host":"a","port":443,"path":"/","headers":[],"body":""},"isDecrypted":false,"isTunnel":false}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate
        let f = try d.decode(Flow.self, from: Data(json.utf8))
        #expect(f.clientPort == nil && f.clientAddress == "127.0.0.1")
    }

    @Test func decodesFlowWithoutAnnotations() throws {
        let json = #"{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"clientAddress":"127.0.0.1","startedAt":0,"request":{"method":"GET","scheme":"https","host":"a","port":443,"path":"/","headers":[],"body":""},"isDecrypted":false,"isTunnel":false}"#
        let f = try JSONDecoder().decode(Flow.self, from: Data(json.utf8))
        #expect(f.annotations == [])
        var flow = Flow(id: FlowID(), clientAddress: "1.2.3.4", startedAt: Date(timeIntervalSince1970: 0), request: .get("http://a/"))
        flow.annotations = [.hidden, .tool("x"), .originalURL("http://a/")]
        #expect(try JSONDecoder().decode(Flow.self, from: JSONEncoder().encode(flow)) == flow)
    }
}
