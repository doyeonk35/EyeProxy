import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import Observation

/// 탭 하나의 보기 상태(스펙 §4.1): 필터·선택·정렬·사이드바·본문 일치 작업과 그 파생 목록·트리.
/// 라이브 탭은 앱의 라이브 세션(`AppModel.liveSession`)·프로세스 귀속을 같이 쓰고, 파일 탭은 연 파일의 것을 따로 갖는다.
@MainActor @Observable
final class SessionTab: Identifiable {
    let id = UUID()
    unowned let model: AppModel
    let session: SessionStore
    let processes: ProcessRegistry
    /// nil = 라이브 탭.
    let fileURL: URL?
    /// 실행 탭만 필터 규칙을 저장한다(스펙 §4.1). 다른 탭의 규칙은 그 탭에만 남는다.
    let persistsRules: Bool
    var isLive: Bool { fileURL == nil }

    /// 라이브: 사이드바에서 고른 항목 이름(없거나 All Requests면 "All Requests"). 파일: 파일 이름.
    var title: String {
        if let fileURL { return fileURL.lastPathComponent }
        switch sidebarSelection {
        case nil, .allFlows?: return "All Requests"
        case .host(let host)?: return host
        case .path(let host, let prefix)?: return host + prefix
        case .scope(let s)?:
            if let host = s.host { return host }
            if let process = s.process { return sidebarTree.apps.first { $0.groupKey == process }?.displayName ?? process }
            if s.device == SidebarTree.thisMac { return "Apps" }
            return sidebarTree.remoteDevices.first { $0.address == s.device }?.displayName ?? s.device ?? "All Requests"
        }
    }

    /// 이 탭을 보이는 창(`MainWindowHost`가 붙인다). 탭 이동 메뉴·상태 막대 Show Prog가 쓴다.
    @ObservationIgnored weak var window: NSWindow?

    /// 화면에 보이는 탭인가(창의 가림 상태). false면 목록·트리 계산을 미루고, true가 되면 한 번 계산한다.
    /// 처음엔 false — 창에 붙어 보이기 전(뒤에서 만든 탭)에는 계산하지 않는다.
    @ObservationIgnored var isOnScreen = false {
        didSet { if isOnScreen, !oldValue { refreshVisibleRows(); sidebarRefresh.now() } }
    }

    /// 목록 필터. 규칙·AND/OR가 바뀌면 저장하고 목록에 반영한다(`filterRulesChanged`).
    var filter: FlowFilter {
        didSet {
            if filter.rules != oldValue.rules || filter.combineWithOr != oldValue.combineWithOr { filterRulesChanged() }
            // 칩·숨김 보기 같은 나머지 조건은 바로 반영한다(규칙은 `appliedRules`가 바뀔 때).
            var rest = filter
            (rest.rules, rest.combineWithOr) = (oldValue.rules, oldValue.combineWithOr)
            if rest != oldValue { refreshVisibleRows() }
        }
    }
    /// 목록 위 필터 막대(스펙 §4). 숨겨도 켜진 규칙은 계속 적용된다.
    var isFilterBarVisible: Bool {
        // 막대 안에 포커스가 있었는데 숨기면(Esc·하단 Filter 버튼) 포커스를 목록으로 돌려 ⌫·화살표가 바로 동작하게.
        didSet { if !isFilterBarVisible, filterBarHasFocus { filterBarHasFocus = false; focusFlowList = true } }
    }
    /// 필터 막대 안에 포커스가 있다(막대가 알린다). 그리기에는 쓰지 않는다.
    @ObservationIgnored var filterBarHasFocus = false
    /// 목록 표에 포커스를 달라는 한 번짜리 요청. 목록이 받아서 끈다.
    var focusFlowList = false
    /// ⌘F가 막대를 보이면 막대가 현재 규칙 검색칸에 포커스를 주고 끈다.
    var focusFilterBar = false
    /// 켜진(적용되는) 규칙이 있다 — 하단 바 Filter 버튼 강조.
    var hasActiveFilterRules: Bool { filter.hasActiveRules }
    /// 목록에 실제로 적용 중인 규칙·AND/OR. 본문 규칙이 바뀌면 백그라운드 판정이 끝난 뒤에 바뀐다(그동안 이전 결과 유지).
    private var appliedRules: FlowFilter { didSet { refreshVisibleRows() } }
    /// 본문 규칙(`bodyMatchRules`) 판정 결과. 흐름 id → 판정한 본문 크기·규칙마다 결과.
    private var bodyMatches: [FlowID: BodyMatch] = [:]
    @ObservationIgnored private var bodyMatchRules: [FilterRule] = []
    @ObservationIgnored private var bodyJob: Task<Void, Never>?
    @ObservationIgnored private var bodyJobGeneration = 0
    /// 돌고 있는 `bodyJob`이 새 규칙 전체 판정인가(아니면 새 흐름만 보는 부분 판정).
    @ObservationIgnored private var bodyJobIsFull = false
    @ObservationIgnored private var rulesDebounce: Task<Void, Never>?
    /// 목록 선택(여러 건 가능 — Repeat). 상세·코멘트 등 한 건용 동작은 `selectedFlowID`를 쓴다.
    var selectedFlowIDs: Set<FlowID> = []
    /// 정확히 한 건이 선택됐을 때 그 흐름.
    var selectedFlowID: FlowID? {
        get { selectedFlowIDs.count == 1 ? selectedFlowIDs.first : nil }
        set { selectedFlowIDs = newValue.map { [$0] } ?? [] }
    }
    /// 기본은 ID 내림차순(최신이 맨 위, Proxyman). 열 머리로 바꾼 정렬은 저장하지 않는다.
    var sortOrder: [KeyPathComparator<FlowRow>] = [KeyPathComparator(\.number, order: .reverse)] { didSet { refreshVisibleRows() } }
    var sidebarSelection: SidebarItem? = .allFlows { didSet { refreshVisibleRows() } }
    /// 목록에 보이는 흐름(세션 순서)과 행(정렬 순서). 사용자 조작은 바로, 트래픽(세션·귀속·본문 판정 변화)은
    /// 묶어서 최대 `rowsRefreshInterval`마다 다시 계산한다 — 요청이 쏟아져도 메인 스레드가 매 이벤트 전체를 다시 거르지 않게(스펙 §1).
    private(set) var visibleFlows: [Flow] = []
    private(set) var visibleRows: [FlowRow] = []
    /// 사이드바 트리·"전체" 개수. 목록처럼 트래픽 중에는 묶어서 다시 만든다.
    private(set) var sidebarTree = SidebarTree.build(flows: [], attribution: [:], devices: [], pinned: [], runtimes: [:])
    private(set) var sidebarFlowCount = 0
    /// 사이드바 아래 필터 칸: 줄 이름으로 거른다.
    var sidebarFilterText = "" { didSet { sidebarRefresh.now() } }
    /// 경로 트리를 펼친 도메인. 펼친 도메인만 경로 트리를 만든다(사이드바와 같이 묶어서 갱신).
    var expandedDomains: Set<String> = [] { didSet { sidebarRefresh.now() } }
    private(set) var pathTrees: [String: [PathNode]] = [:]
    // 보이지 않는 탭은 계산하지 않는다(관찰도 걸지 않음). 앞으로 나오면 `isOnScreen`이 다시 건다.
    @ObservationIgnored private lazy var rowsRefresh = ThrottledRefresh { [weak self] in
        if let self, isOnScreen { computeVisibleRows() }
    }
    @ObservationIgnored private lazy var sidebarRefresh = ThrottledRefresh { [weak self] in
        if let self, isOnScreen { computeSidebar() }
    }
    /// Flow ▸ Delete All 확인 대기(필터가 숨긴 행이 있을 때만). 목록이 alert를 띄운다.
    var pendingDeleteAll: (ids: Set<FlowID>, hiddenCount: Int)?
    /// Flow ▸ Add Comment…로 코멘트를 편집 중인 흐름. 메인 창이 시트를 띄운다.
    var commentingFlowID: FlowID?

    init(model: AppModel, session: SessionStore, processes: ProcessRegistry, fileURL: URL?, restoreSavedRules: Bool) {
        // 마지막 필터 규칙을 되살린다. 켜진 규칙이 있으면 막대를 보인 채로 시작한다.
        // 저장 프로퍼티를 모두 채우기 전에 넣으므로 `didSet`(규칙 저장·판정)을 거치지 않는다.
        let saved = restoreSavedRules ? model.settings.filterRules : FlowFilter()
        filter = saved
        appliedRules = saved
        bodyMatchRules = saved.activeBodyRules
        isFilterBarVisible = saved.hasActiveRules
        self.model = model
        self.session = session
        self.processes = processes
        self.fileURL = fileURL
        persistsRules = restoreSavedRules
    }

    func clear() {
        session.clear()
        if isLive { processes.clear() }
        selectedFlowID = nil
        // 지우면 목록이 비어 선택된 행이 사라진다 → 보이지 않는 필터가 남지 않게.
        if let s = sidebarSelection, s != .allFlows { sidebarSelection = .allFlows }
        bodyMatches = [:]
        refreshVisibleRows()
    }

    /// Flow ▸ Delete(스펙 §5). 보이는 행만 지운다 — 선택에 남은, 필터·사이드바가 숨긴 행은 몰래 지우지 않는다.
    /// 선택이 지워지면 지운 행 바로 아래 보이는 행으로(없으면 위) 옮긴다.
    func deleteFlows(_ ids: Set<FlowID>) {
        // 트래픽 중 묶어 둔 목록은 최대 250 ms 늦다 — 지우기 전에 지금 화면과 같게 맞춘다.
        refreshVisibleRows()
        let order = visibleRows.map(\.id)
        let ids = ids.intersection(order)
        guard !ids.isEmpty else { return }
        let next = order.lastIndex(where: ids.contains).flatMap { last in
            order[(last + 1)...].first { !ids.contains($0) } ?? order[..<last].last { !ids.contains($0) }
        }
        session.remove(ids: ids)
        for id in ids { processes.remove(id); bodyMatches[id] = nil }
        refreshVisibleRows()
        if !selectedFlowIDs.isDisjoint(with: ids) { selectedFlowID = next }
    }

    /// Flow ▸ Delete All: 보이는 행만 지운다. 필터·사이드바가 숨긴 행이 있으면 확인부터 받는다.
    func deleteVisibleFlows() {
        refreshVisibleRows()
        let visible = Set(visibleFlows.map(\.id))
        guard !visible.isEmpty else { return }
        let hidden = session.flows.count - visible.count
        if hidden > 0 { pendingDeleteAll = (visible, hidden) } else { deleteFlows(visible) }
    }

    // MARK: - 세션 파일 · cURL

    func saveSession() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [AppModel.sessionType]
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmm"
        // 파일 탭은 그 파일 이름(HAR 탭이면 확장자만 세션으로).
        let name = fileURL?.deletingPathExtension().lastPathComponent ?? "Prog-\(stamp.string(from: .now))"
        panel.nameFieldStringValue = "\(name).\(SessionDocument.pathExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let (flows, log, attribution, comments, highlights, numbers) =
            (session.flows, session.connectionLog, processes.attribution, session.comments, session.highlights, session.numbersByID)
        do {
            try await Task.detached {
                try SessionDocument.save(flows: flows, connectionLog: log, processes: attribution, comments: comments,
                                         highlights: highlights, numbers: numbers, to: url)
            }.value
            model.noteRecent(url)
        } catch {
            model.systemError = String(localized: "세션을 저장하지 못했습니다: \(error.localizedDescription)")
        }
    }

    func copyCurl(_ id: FlowID) {
        guard let flow = session.flow(id) else { return }
        NSPasteboard.general.clearContents()
        // Tools ▸ Add --proxy flag into cURL command: 툴바 캡슐과 같은 IP·포트.
        let proxy = model.settings.curlProxyFlag
            ? "http://\(model.lanAddresses.first ?? "127.0.0.1"):\(model.runningPort ?? model.settings.port)" : nil
        NSPasteboard.general.setString(CurlExport.command(for: flow.request, proxy: proxy), forType: .string)
    }

    // MARK: - 목록

    /// 사용자 조작(규칙·정렬·사이드바 선택·삭제): 보이는 행을 지금 다시 계산한다.
    /// 보이지 않는 탭도 이번 한 번은 계산한다(관찰은 걸지 않음) — 지우기·내보내기가 낡은 목록을 읽지 않게.
    func refreshVisibleRows() { if isOnScreen { rowsRefresh.now() } else { computeVisibleRows() } }

    private func computeVisibleRows() {
        let flows = computeVisibleFlows()
        visibleFlows = flows
        visibleRows = flows.map { FlowRow(flow: $0, number: session.number($0.id) ?? 0) }.sorted(using: sortOrder)
    }

    private func computeVisibleFlows() -> [Flow] {
        var f = filter
        (f.rules, f.combineWithOr) = (appliedRules.rules, appliedRules.combineWithOr)
        sidebarSelection?.apply(to: &f)
        let p = f.prepared()
        // Client 이름은 계산이 무거워 Client 규칙이 있을 때만 만든다.
        let needsClient = f.rules.contains { $0.isActive && $0.key == .client }
        // 본문 규칙은 여기서 풀지 않고 백그라운드 판정 결과를 쓴다. 아직 판정 전(새 흐름·본문이 바뀐 흐름)이면 맞지 않음으로 두고 판정을 건다.
        let usesBody = !p.bodyRules.isEmpty
        var unmatched = false
        let flows = session.flows.filter {
            var hits: [Bool]?
            if usesBody {
                let cached = bodyMatches[$0.id]
                if cached?.sizes != Self.bodySizes($0) { unmatched = true }
                hits = cached?.hits ?? []
            }
            let subject = FilterSubject(flow: $0, number: session.number($0.id) ?? 0, comment: session.comments[$0.id],
                                        highlight: session.highlights[$0.id], client: needsClient ? clientName(for: $0) : "")
            return p.matches(subject, process: processKey(for: $0), bodyHits: hits)
        }
        if unmatched, bodyJob == nil, rulesDebounce == nil { startBodyMatching(appliedRules, full: false) }
        return flows
    }

    // MARK: - 필터 막대

    /// ⌘F(목록 쪽 포커스): 막대를 보이고 현재 규칙 검색칸에 포커스.
    func showFilterBar() {
        isFilterBarVisible = true
        focusFilterBar = true
    }

    /// 판정한 흐름의 본문 크기. 바뀌면(응답 도착 등) 다시 판정한다.
    private struct BodyMatch { let sizes: [Int]; let hits: [Bool] }
    nonisolated private static func bodySizes(_ flow: Flow) -> [Int] { [flow.request.body.count, flow.response?.body.count ?? -1] }

    /// 규칙이 바뀌었다: 저장하고, 가벼운 규칙만 바뀌었으면 바로, 본문 규칙이 바뀌었으면 디바운스 뒤 백그라운드에서 판정한다(스펙 §4 성능).
    private func filterRulesChanged() {
        if persistsRules { model.settings.filterRules = filter }
        rulesDebounce?.cancel()
        rulesDebounce = nil
        let body = filter.activeBodyRules
        if body == bodyMatchRules {
            // 본문 규칙은 그대로다. 되돌린 입력의 새 전체 판정만 버리고(새 흐름 부분 판정은 계속),
            // 꺼진·빈 규칙만 바뀌었으면 목록은 그대로 둔다.
            if bodyJobIsFull { cancelBodyJob() }
            if filter.rules.filter(\.isActive) != appliedRules.rules.filter(\.isActive)
                || filter.combineWithOr != appliedRules.combineWithOr { appliedRules = filter }
            return
        }
        cancelBodyJob()
        if body.isEmpty {
            (bodyMatches, bodyMatchRules) = ([:], [])
            appliedRules = filter
            return
        }
        rulesDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            rulesDebounce = nil
            startBodyMatching(filter, full: true)
        }
    }

    private func cancelBodyJob() {
        bodyJob?.cancel()
        bodyJob = nil
        bodyJobIsFull = false
        bodyJobGeneration += 1
    }

    /// 본문 규칙을 메인 밖에서 판정한다. full이면 모든 흐름을 새 규칙으로, 아니면 아직 판정하지 않은 흐름만.
    /// 가장 최근에 시작한 작업의 결과만 반영한다(이전 작업은 취소).
    private func startBodyMatching(_ rules: FlowFilter, full: Bool) {
        bodyJob?.cancel()
        bodyJobIsFull = full
        bodyJobGeneration += 1
        let generation = bodyJobGeneration
        let flows = full ? session.flows : session.flows.filter { bodyMatches[$0.id]?.sizes != Self.bodySizes($0) }
        bodyJob = Task.detached(priority: .userInitiated) { [weak self] in
            let p = rules.prepared()
            var result: [FlowID: BodyMatch] = [:]
            for flow in flows {
                if Task.isCancelled { return }
                result[flow.id] = BodyMatch(sizes: Self.bodySizes(flow), hits: p.bodyHits(FilterSubject(flow: flow)))
            }
            await self?.applyBodyMatches(result, rules: rules, full: full, generation: generation)
        }
    }

    private func applyBodyMatches(_ result: [FlowID: BodyMatch], rules: FlowFilter, full: Bool, generation: Int) {
        guard generation == bodyJobGeneration else { return }
        bodyJob = nil
        bodyJobIsFull = false
        guard full else { bodyMatches.merge(result) { $1 }; return }
        // 그사이 가벼운 규칙·AND/OR만 바뀌었을 수 있다(본문 규칙이 바뀌었으면 generation이 달라 여기 오지 않는다).
        bodyMatches = result
        bodyMatchRules = rules.activeBodyRules
        appliedRules = filter
    }

    /// View ▸ Auto Select(스펙 §6): 켜져 있으면 보이는 행 중 최신을 선택하고 그 id를 돌려준다(목록이 스크롤한다).
    func selectLatestIfAuto() -> FlowID? {
        guard model.settings.autoSelectLatest,
              let id = AutoSelect.latest(in: visibleFlows, number: { session.number($0) ?? 0 }) else { return nil }
        selectedFlowID = id
        return id
    }

    /// 목록에서 사용자가 바꾼 선택(클릭·키보드). 이 경로만 Auto Select를 끈다 —
    /// Delete·세션 열기·Auto Select 같은 프로그램 선택은 `selectedFlowIDs`에 바로 쓰므로 끄지 않는다.
    func userSelect(_ ids: Set<FlowID>) {
        // 행이 바뀔 때 Table이 같은 선택을 다시 써도 사용자 변경으로 보지 않는다.
        guard ids != selectedFlowIDs else { return }
        if model.settings.autoSelectLatest, AutoSelect.shouldDisable(userSelected: ids, autoSelected: AutoSelect.latest(in: visibleFlows, number: { session.number($0) ?? 0 })) {
            model.settings.autoSelectLatest = false
        }
        selectedFlowIDs = ids
    }

    func processKey(for flow: Flow) -> String? { processes.attribution[flow.id]?.groupKey }

    /// 목록 Client 열과 Export가 같이 쓰는 이름: 프로세스 귀속 → (루프백이 아니면) 기기 이름 → 주소. 없으면 "".
    func clientName(for flow: Flow) -> String {
        if let identity = processes.attribution[flow.id] { return identity.displayName(runtimes: model.simulatorRuntimes) }
        guard !FlowFilter.isLoopback(flow.clientAddress) else { return "" }
        return model.devices.devices.first { $0.address == flow.clientAddress }?.displayName ?? flow.clientAddress
    }

    /// 사이드바·배지가 세는 흐름. "숨김 포함"이 꺼져 있으면 Block List로 숨긴 흐름을 뺀다.
    var sidebarFlows: [Flow] {
        filter.includeHidden ? session.flows : session.flows.filter { !$0.annotations.contains(.hidden) }
    }

    private func computeSidebar() {
        let flows = sidebarFlows
        sidebarFlowCount = flows.count
        sidebarTree = SidebarTree.build(flows: flows, attribution: processes.attribution, devices: model.devices.devices,
                                        pinned: model.settings.pinnedHosts, runtimes: model.simulatorRuntimes).filtered(sidebarFilterText)
        pathTrees = Dictionary(uniqueKeysWithValues: expandedDomains.map { ($0, SidebarTree.pathTree(for: $0, flows: flows)) })
    }
}
