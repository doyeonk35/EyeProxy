import EyeProxyCore
import Foundation
import Observation

public enum BreakpointPhase: String, Codable, Sendable {
    case request, response
}

/// 멈춘 요청/응답 한 건.
public struct PausedItem: Identifiable, Sendable {
    public let id: UUID
    public let flowID: FlowID
    public let phase: BreakpointPhase
    public let ruleName: String
    public let request: FlowRequest
    public let response: FlowResponse?

    public init(id: UUID = UUID(), flowID: FlowID, phase: BreakpointPhase, ruleName: String,
                request: FlowRequest, response: FlowResponse? = nil) {
        self.id = id
        self.flowID = flowID
        self.phase = phase
        self.ruleName = ruleName
        self.request = request
        self.response = response
    }
}

public enum BreakpointResolution: Sendable, Equatable {
    case continueOriginal
    case executeRequest(FlowRequest)
    case executeResponse(FlowResponse)
    case drop
    /// 429 또는 503.
    case abort(status: Int)
}

/// 멈춘 건 대기열. 각 건은 `resolve`·`releaseAll`·호출 Task 취소(클라이언트 끊김) 중 먼저 오는 것으로 정확히 한 번 풀린다.
@MainActor @Observable
public final class BreakpointCenter {
    public private(set) var pending: [PausedItem] = []
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<BreakpointResolution, Never>] = [:]
    /// 요청 단계에서 Abort로 응답을 만든 흐름. 그 응답은 응답 단계에서 다시 멈추지 않는다(꺼낼 때 지운다).
    @ObservationIgnored private var aborted: Set<FlowID> = []

    public init() {}

    /// 목록에 넣고 풀릴 때까지 기다린다. 호출 Task가 취소되면 목록에서 빼고 `.continueOriginal`.
    public func pause(_ item: PausedItem) async -> BreakpointResolution {
        await withTaskCancellationHandler {
            await withCheckedContinuation { c in
                guard !Task.isCancelled else { return c.resume(returning: .continueOriginal) }
                waiters[item.id] = c
                pending.append(item)
            }
        } onCancel: {
            Task { @MainActor in self.resolve(item.id, with: .continueOriginal) }
        }
    }

    /// 이미 풀린 id면 아무것도 하지 않는다.
    public func resolve(_ id: UUID, with resolution: BreakpointResolution) {
        pending.removeAll { $0.id == id }
        waiters.removeValue(forKey: id)?.resume(returning: resolution)
    }

    /// 앱 종료 시: 전부 원본대로 보낸다.
    public func releaseAll() {
        for id in Array(waiters.keys) { resolve(id, with: .continueOriginal) }
        aborted.removeAll()
    }

    func markAborted(_ id: FlowID) { aborted.insert(id) }

    /// 표시돼 있었으면 지우고 true.
    func consumeAborted(_ id: FlowID) -> Bool { aborted.remove(id) != nil }
}
