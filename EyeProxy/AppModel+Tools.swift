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
            rules: rules.ruleSet, switches: settings.toolSwitches, breakpoints: breakpoints,
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
}
