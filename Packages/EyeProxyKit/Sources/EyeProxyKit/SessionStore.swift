import EyeProxyCore
import Foundation
import Observation

@Observable @MainActor
public final class SessionStore {
    public private(set) var flows: [Flow] = []
    public private(set) var connectionLog: [ConnectionLogEntry] = []
    /// 사용자 코멘트(Flow ▸ Add Comment…). 있는 흐름에만 붙는다.
    public private(set) var comments: [FlowID: String] = [:]
    @ObservationIgnored private var index: [FlowID: Int] = [:]
    @ObservationIgnored private var numbers: [FlowID: Int] = [:]
    @ObservationIgnored private var next = 1
    private static let logCap = 1000

    public init() {}

    public func apply(_ event: FlowEvent) {
        switch event {
        case .requestStarted(let flow):
            index[flow.id] = flows.count
            numbers[flow.id] = next; next += 1
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
        case .requestSent(let id, let request):
            guard let i = index[id] else { return }
            // `.sentURL`(Preserve the Original URL)이면 표시 URL은 두고 나머지만 바꾸며, 주석은 최종 URL로 고친다.
            if let s = flows[i].annotations.firstIndex(where: { if case .sentURL = $0 { true } else { false } }) {
                let shown = flows[i].request
                flows[i].request = request
                (flows[i].request.scheme, flows[i].request.host, flows[i].request.port, flows[i].request.path) =
                    (shown.scheme, shown.host, shown.port, shown.path)
                flows[i].annotations[s] = .sentURL(request.url)
            } else {
                flows[i].request = request
            }
        case .annotated(let id, let annotation):
            guard let i = index[id] else { return }
            if annotation == .unrecorded {
                remove(at: i)
            } else if !flows[i].annotations.contains(annotation) {
                flows[i].annotations.append(annotation)
            }
        }
    }

    /// 번호는 붙은 그대로 둔다(빈 번호 허용). 가장 최근 번호면 `next`만 되돌린다. `index`는 위치이므로 뒤를 다시 맞춘다.
    private func remove(at i: Int) {
        let removed = flows.remove(at: i)
        index[removed.id] = nil
        if numbers.removeValue(forKey: removed.id) == next - 1 { next -= 1 }
        comments[removed.id] = nil
        for k in i..<flows.count { index[flows[k].id] = k }
    }

    /// `numbers`가 nil이면 순서대로 1부터, 있으면 그 번호를 쓰고 빠진 흐름은 최대 번호 뒤로 순서대로 붙인다.
    public func replace(flows: [Flow], connectionLog: [ConnectionLogEntry] = [], comments: [FlowID: String] = [:],
                        numbers: [FlowID: Int]? = nil) {
        self.flows = flows
        index = Dictionary(flows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, last in last })
        self.numbers = (numbers ?? [:]).filter { index[$0.key] != nil }
        next = (self.numbers.values.max() ?? 0) + 1
        for f in flows where self.numbers[f.id] == nil { self.numbers[f.id] = next; next += 1 }
        self.connectionLog = connectionLog
        self.comments = comments.filter { index[$0.key] != nil && !$0.value.isEmpty }
    }

    public func clear() { replace(flows: []) }

    /// nil·빈 문자열 = 삭제. 목록에 없는 흐름은 무시한다.
    public func setComment(_ text: String?, for id: FlowID) {
        guard index[id] != nil else { return }
        comments[id] = text?.isEmpty == false ? text : nil
    }

    public func number(_ id: FlowID) -> Int? { numbers[id] }

    /// 흐름별 안정 번호 전체(세션 저장용).
    public var numbersByID: [FlowID: Int] { numbers }

    public func flow(_ id: FlowID) -> Flow? { index[id].map { flows[$0] } }
}
