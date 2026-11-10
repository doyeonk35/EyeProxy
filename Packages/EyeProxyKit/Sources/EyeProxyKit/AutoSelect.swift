import EyeProxyCore
import Foundation

/// View ▸ Auto Select the Latest Request(스펙 §6).
public enum AutoSelect {
    /// 보이는 행 중 가장 최근 요청: 시작 시각이 가장 늦은 행, 같으면 번호가 큰 행. 정렬 순서와 무관하다.
    public static func latest(in rows: [FlowRow]) -> FlowID? {
        rows.max { ($0.startedAt, $0.number) < ($1.startedAt, $1.number) }?.id
    }

    /// 같은 규칙을 FlowRow 없이 — 목록 정렬·행 생성 없이 흐름에서 바로 고른다.
    public static func latest(in flows: [Flow], number: (FlowID) -> Int) -> FlowID? {
        flows.max { ($0.startedAt, number($0.id)) < ($1.startedAt, number($1.id)) }?.id
    }

    /// 사용자가 목록에서 고른 선택이 자동 선택한 행과 다르면 Auto Select를 끈다.
    public static func shouldDisable(userSelected: Set<FlowID>, autoSelected: FlowID?) -> Bool {
        userSelected != Set([autoSelected].compactMap { $0 })
    }
}
