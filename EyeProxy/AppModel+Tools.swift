import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import Observation

extension AppModel {
    static let rulesDirectory = supportDirectory.appending(path: "rules")

    /// 현재 규칙·스위치로 만든 체인. 서버 시작 때와 `applyTools()`가 쓴다.
    func toolChain() -> InterceptorChain {
        let resolver = self.resolver
        return ToolPipeline.chain(
            rules: rules.ruleSet, switches: settings.toolSwitches, sslPolicy: settings.sslPolicy, breakpoints: breakpoints,
            appPath: { [weak self] address, clientPort in
                // Mac 앱 판별은 루프백 클라이언트만 가능하다(lsof).
                guard FlowFilter.isLoopback(address), let clientPort, let proxyPort = await self?.runningPort else { return nil }
                return await resolver.resolve(port: clientPort, proxyPort: proxyPort)?.path
            },
            base: [CAProfileResponder(certificateAuthority: certificateAuthority)])
    }

    /// 규칙(`rules.revision`)이나 도구 스위치가 바뀌면 체인을 다시 만든다. 한 번 부르면 계속 다시 걸린다.
    func observeTools() {
        withObservationTracking {
            _ = rules.revision
            _ = settings.toolSwitches
        } onChange: { [weak self] in
            // onChange는 값이 바뀌기 전에 불린다 → 다음 턴에 읽는다.
            Task { @MainActor in
                self?.observeTools()
                await self?.applyTools()
            }
        }
    }

    /// 멈춘 Breakpoint 신호를 메인 창과 무관하게 낸다(§2 반목표): Dock 배지에 대기 수, 새로 멈추면 Breakpoint 창을 열고 Dock 아이콘을 튀긴다.
    func observeBreakpoints() {
        withObservationTracking {
            _ = breakpoints.pending.count
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeBreakpoints()
                self?.pendingBreakpointsChanged()
            }
        }
    }

    private func pendingBreakpointsChanged() {
        let count = breakpoints.pending.count
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
        if count > lastPendingBreakpoints {
            openBreakpointsWindow?()
            NSApp.activate()
            NSApp.requestUserAttention(.informationalRequest)
        }
        lastPendingBreakpoints = count
    }

    /// 호출 순서대로 직렬화하고 실행 시점의 규칙을 읽으므로 마지막 변경이 이긴다. 진행 중인 요청은 이전 체인을 그대로 쓴다.
    func applyTools() async {
        let previous = toolsUpdate
        let update = Task {
            await previous?.value
            await server?.update(interceptors: toolChain())
        }
        toolsUpdate = update
        await update.value
    }

    // MARK: - Compose·Repeat (§5.8)

    /// 프록시가 떠 있을 때만. 요청은 이 프록시를 거쳐 나가 목록에 기록된다.
    var composeClient: ComposeClient? {
        runningPort.map { ComposeClient(proxyPort: $0, trustRootDER: certificateAuthority.certificateDER) }
    }

    /// 선택한 요청을 그대로 다시 보낸다(창 없이). 결과는 메인 목록의 새 행으로 보인다.
    func repeatFlows(_ ids: Set<FlowID>) {
        guard let client = composeClient else {
            systemError = String(localized: "프록시가 실행 중이 아닙니다")
            return
        }
        let noCache = settings.toolSwitches.repeatNoCache
        let timeout = settings.requestTimeoutInterval   // Tools ▸ Request Timeout
        guard let session = activeTab?.session else { return }
        // 목록 순서대로 보낸다.
        for flow in session.flows where ids.contains(flow.id) && !flow.isTunnel {
            let request = noCache ? NoCachingInterceptor.noCache(flow.request) : flow.request
            Task { _ = try? await client.send(request, timeout: timeout) }
        }
    }
}

/// 우클릭 ▸ Tools ▸ … 로 연 새 규칙의 매칭 칸(`MatchRule(prefilledFrom:)` — 쿼리 뺀 URL + 쿼리 무시).
struct PendingNewRule: Equatable {
    let windowID: String
    let flowID: FlowID
    let match: MatchRule

    init(windowID: String, flow: Flow) {
        self.windowID = windowID
        flowID = flow.id
        match = MatchRule(prefilledFrom: flow.request)
    }
}
