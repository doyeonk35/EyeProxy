import EyeProxyCore
import Foundation
import Observation

@Observable @MainActor
public final class SessionStore {
    public private(set) var flows: [Flow] = []
    public private(set) var connectionLog: [ConnectionLogEntry] = []
    @ObservationIgnored private var index: [FlowID: Int] = [:]
    private static let logCap = 1000

    public init() {}

    public func apply(_ event: FlowEvent) {
        switch event {
        case .requestStarted(let flow):
            index[flow.id] = flows.count
            flows.append(flow)
        case .responseReceived(let id, let response, let completedAt):
            guard let i = index[id] else { return }
            flows[i].response = response
            flows[i].completedAt = completedAt
        case .failed(let id, let error, let completedAt):
            guard let i = index[id] else { return }
            flows[i].error = error
            flows[i].completedAt = completedAt
        case .connectionLog(let entry):
            connectionLog.append(entry)
            if connectionLog.count > Self.logCap { connectionLog.removeFirst(connectionLog.count - Self.logCap) }
        }
    }

    public func replace(flows: [Flow], connectionLog: [ConnectionLogEntry] = []) {
        self.flows = flows
        index = Dictionary(flows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, last in last })
        self.connectionLog = connectionLog
    }

    public func clear() { replace(flows: []) }

    public func flow(_ id: FlowID) -> Flow? { index[id].map { flows[$0] } }
}
