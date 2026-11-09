import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func row(_ number: Int, at seconds: TimeInterval) -> FlowRow {
    let f = Flow.fixture(client: "1", decrypted: true)
    let flow = Flow(id: f.id, clientAddress: f.clientAddress, startedAt: Date(timeIntervalSince1970: seconds), request: f.request)
    return FlowRow(flow: flow, number: number)
}

@Test func latestPicksNewestStartedAt() {
    let old = row(9, at: 100), new = row(2, at: 200), tieLow = row(3, at: 300), tieHigh = row(4, at: 300)
    #expect(AutoSelect.latest(in: []) == nil)
    // 정렬 순서(시간 내림차순 등)와 무관하게 시작 시각이 가장 늦은 행.
    #expect(AutoSelect.latest(in: [new, old]) == new.id)
    #expect(AutoSelect.latest(in: [old, new]) == new.id)
    // 같은 시각이면 번호가 큰 행.
    #expect(AutoSelect.latest(in: [tieHigh, old, tieLow]) == tieHigh.id)
    #expect(AutoSelect.latest(in: [tieLow, tieHigh, new]) == tieHigh.id)
}

@Test func userSelectionDisablesAutoSelect() {
    let a = FlowID(), b = FlowID()
    #expect(!AutoSelect.shouldDisable(userSelected: [a], autoSelected: a))
    #expect(AutoSelect.shouldDisable(userSelected: [b], autoSelected: a))
    #expect(AutoSelect.shouldDisable(userSelected: [a, b], autoSelected: a))
    #expect(AutoSelect.shouldDisable(userSelected: [], autoSelected: a))
    #expect(AutoSelect.shouldDisable(userSelected: [a], autoSelected: nil))
    #expect(!AutoSelect.shouldDisable(userSelected: [], autoSelected: nil))
}
