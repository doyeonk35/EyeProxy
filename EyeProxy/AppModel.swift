import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum ServerState: Equatable {
    case stopped
    case running(port: Int)
    case failed(message: String)
}

@MainActor @Observable
final class AppModel {
    static let supportDirectory = URL.applicationSupportDirectory.appending(path: "com.tv.eyeproxy")
    static let caDirectory = supportDirectory.appending(path: "ca")

    let settings = AppSettings()
    /// 라이브 세션(앱에 하나). 라이브 탭은 모두 이 세션과 `processes`를 같이 쓴다(스펙 §4.1).
    let liveSession = SessionStore()
    let processes = ProcessRegistry()
    let rules = RuleStore(directory: AppModel.rulesDirectory)
    let breakpoints = BreakpointCenter()
    @ObservationIgnored let resolver = ProcessResolver()
    let devices: DeviceRegistry
    /// 초기화(`resetCertificateAuthority`)로 바뀔 수 있다. 서버·체인·Compose는 매번 이 값을 읽는다.
    private(set) var certificateAuthority: CertificateAuthority
    /// 새로 만든 CA를 저장하지 못했으면 그 이유. 매 실행 새 루트 CA가 되므로 Task 15 인증서 화면에서 표시한다.
    let caSaveError: String?
    private(set) var serverState: ServerState = .stopped
    /// 열린 탭. 키 = 탭 id.
    private(set) var tabs: [UUID: SessionTab] = [:]
    /// 메뉴 명령이 다루는 탭(앞 창의 탭).
    var activeTab: SessionTab?
    /// 실행할 때 여는 라이브 탭. 마지막 필터 규칙을 되살린다.
    @ObservationIgnored private(set) lazy var mainTab = makeTab(fileURL: nil, session: liveSession, processes: processes, restoreSavedRules: true)
    /// Finder·`open -a`로 연 파일의 탭(`AppDelegate`). 앞 탭의 `MainWindow`가 창을 열고 비운다.
    var pendingOpenTabIDs: [UUID] = []
    /// 우클릭 ▸ Tools로 열 새 규칙. 해당 도구 창이 꺼내 편집기를 연다.
    var pendingNewRule: PendingNewRule?
    /// 별도 창 편집기(`ToolEditorStyle.window`)로 넘기는 규칙. 키 = 규칙 id.
    var editorDrafts: [String: any ToolRule] = [:]
    /// 우클릭 ▸ Tools ▸ Map Local…로 미리 채운 HTTP 메시지. 키 = 규칙 id. Map Local 편집기가 꺼낸다.
    var editorMessages: [String: String] = [:]
    var settingsTab: SettingsTab = .general
    /// Certificate 창의 선택 섹션. Certificate 메뉴가 바꾼 뒤 창을 연다.
    var certificateSection: CertificateSection = .mac
    /// 개발 환경 섹션에서 고른 플랫폼. Certificate 메뉴가 바꾼 뒤 창을 연다.
    var developmentPlatform: DevPlatform = .httpClients
    /// Android 섹션의 탭. Certificate 메뉴가 바꾼 뒤 창을 연다.
    var androidTab: AndroidTab = .device
    /// Edit and Repeat…로 Compose 창에 채울 요청. Compose 창이 꺼내 쓴다.
    var composeSeed: FlowRequest?
    /// 규칙 파일 경고(`rules.loadWarnings`) alert. 새 경고가 생기거나 툴바 경고를 누르면 켠다.
    var showRuleWarnings = false
    /// Breakpoint 창을 여는 동작. 메인 창이 등록한다(창이 닫혀도 앱 수준 관찰이 부른다).
    @ObservationIgnored var openBreakpointsWindow: (@MainActor () -> Void)?
    @ObservationIgnored var lastPendingBreakpoints = 0
    /// Sparkle이 새 버전을 찾았다(`AppDelegate`의 updater delegate). 툴바 "New Update" 배지.
    var updateAvailable = false
    /// Sparkle 업데이트 확인. 앱이 시작하면 `AppDelegate`가 등록한다.
    @ObservationIgnored var checkForUpdates: @MainActor () -> Void = {}
    /// Advanced ▸ Show Update Notification at Launch = Sparkle `automaticallyChecksForUpdates`(Sparkle 자기 키에 저장).
    /// `AppDelegate`가 시작할 때 Sparkle 값을 넣고 `setAutomaticUpdateChecks`를 등록한다.
    var automaticUpdateChecks = true { didSet { setAutomaticUpdateChecks(automaticUpdateChecks) } }
    @ObservationIgnored var setAutomaticUpdateChecks: @MainActor (Bool) -> Void = { _ in }

    // 온보딩(기기 윈도우)
    @ObservationIgnored let systemProxy = SystemProxy(backupURL: supportDirectory.appending(path: "system-proxy-backup.json"))
    private(set) var macCaptureEnabled = false
    private(set) var macCaptureBusy = false
    private(set) var macCAInstalled = false
    private(set) var bootedSimulators: [SimulatorDevice] = []
    /// 시작 시 남아 있던 시스템 프록시 백업(비정상 종료). nil로 만들면 alert가 닫힌다.
    var pendingProxyRestore: SystemProxyBackup?
    /// 디스크에 원본 백업이 있다 = 시스템 프록시가 EyeProxy를 가리키고 있다(캡처 중이거나 복원 전).
    private(set) var systemProxyBackupExists = false
    /// 백업이 없는데 실효 프록시(`scutil --proxy`)가 EyeProxy를 가리킨다 = VPN 서비스에 복사본이 남았다.
    /// 이때 토글은 켜진 것으로 보이고, 끄면 disable이 복사본을 정리한다.
    private(set) var effectiveProxyLeftover = false
    /// 기본 서비스가 VPN(GlobalProtect 등)이다 → 켜고 끌 때 VPN State 키를 관리자 권한으로 쓴다.
    private(set) var vpnPrimaryDetected = false
    /// 시스템 프록시·CA 설치·프로필 저장 실패. 기기 창(없으면 메인 창)에 alert로 표시한다.
    var systemError: String?
    /// 오류가 아닌 안내(CA 초기화 결과 등). 창이 alert로 띄운다.
    var infoMessage: String?
    /// 기기 창이 열려 있으면 오류 alert는 그 창이 맡는다(메인 창은 띄우지 않음).
    var devicesWindowOpen = false

    /// 종료 중이면 시스템 프록시를 다시 켜지 않는다(종료 경로가 끈 뒤에 켜지는 경쟁 방지).
    @ObservationIgnored var quitting = false
    @ObservationIgnored private(set) var server: ProxyServer?
    @ObservationIgnored var toolsUpdate: Task<Void, Never>?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private var settingsUpdate: Task<Void, Never>?
    @ObservationIgnored private var captureUpdate: Task<Void, Never>?
    @ObservationIgnored private var restartUpdate: Task<Void, Never>?
    /// 시스템 프록시를 마지막으로 켠 포트(끌 때 "우리 것"을 가려내는 기준).
    @ObservationIgnored private var capturePort: Int?
    @ObservationIgnored private var didAutoOverride = false

    init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        devices = DeviceRegistry(storageURL: Self.supportDirectory.appending(path: "devices.json"))
        (certificateAuthority, caSaveError) = Self.loadOrCreateCA()
        // 이 실행은 아직 캡처를 켜지 않았으므로 백업이 있으면 이전 실행이 복원하지 못한 것이다.
        pendingProxyRestore = systemProxy.pendingRestore()
        systemProxyBackupExists = pendingProxyRestore != nil
        // 지연 로드가 뷰 렌더링 중에 관찰 상태(loadWarnings)를 바꾸지 않도록 미리 모두 읽는다.
        _ = rules.ruleSet
        _ = rules.customNetworkProfiles
        _ = rules.breakpointTemplates
        // 저장된 폴더가 Proxyman 폴더와 겹치면(직접 고친 설정 등) 무시하고 기본 폴더를 쓴다.
        rules.mapLocalFolderOverride = settings.mapLocalDefaultFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            .flatMap { ProxymanImporter.isSafeWriteTarget($0) ? $0 : nil }
        observeTools()
        observeBreakpoints()
        activeTab = mainTab
        // 백업 없이 VPN 복사본만 남은 경우(종료 때 관리자 인증 취소 등)도 시작 시 알린다.
        Task { await refreshEffectiveProxyWarning() }
    }

    /// 탭을 만들어 `tabs`에 등록한다.
    func makeTab(fileURL: URL?, session: SessionStore, processes: ProcessRegistry, restoreSavedRules: Bool) -> SessionTab {
        let tab = SessionTab(model: self, session: session, processes: processes, fileURL: fileURL, restoreSavedRules: restoreSavedRules)
        tabs[tab.id] = tab
        return tab
    }

    func tab(_ id: UUID) -> SessionTab? { tabs[id] }

    /// 값 없이 여는 메인 창(실행·Dock 클릭·탭 막대 +)의 탭. 처음 한 번은 실행 탭(`mainTab`, 마지막 필터 규칙)이다.
    func defaultTabID() -> UUID {
        guard mainTabHandedOut else { mainTabHandedOut = true; return mainTab.id }
        return newLiveTabID()
    }
    @ObservationIgnored private var mainTabHandedOut = false

    /// New Session ⌘T: 빈 필터로 라이브 세션을 보는 새 탭.
    func newLiveTabID(selecting item: SidebarItem? = nil) -> UUID {
        let tab = makeTab(fileURL: nil, session: liveSession, processes: processes, restoreSavedRules: false)
        if let item { tab.sidebarSelection = item }
        return tab.id
    }

    /// 사이드바 ▸ Open as New Tab: 같은 세션·귀속을 보고, 그 항목을 고른 새 탭.
    func newTabID(sharing tab: SessionTab, selecting item: SidebarItem) -> UUID {
        let new = makeTab(fileURL: tab.fileURL, session: tab.session, processes: tab.processes, restoreSavedRules: false)
        new.sidebarSelection = item
        return new.id
    }

    /// 탭 창이 닫혔다. 닫힌 탭은 다시 계산하지 않는다.
    func closeTab(_ id: UUID) {
        tabs[id]?.isOnScreen = false
        tabs[id] = nil
        if activeTab?.id == id { activeTab = nil }
    }

    /// 상태 막대 Show Prog: 열린 메인 창을 앞으로, 없으면 새 라이브 탭 창.
    func showMainWindow(openWindow: OpenWindowAction) {
        NSApp.activate()
        if let window = activeTab?.window ?? tabs.values.lazy.compactMap(\.window).first {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    /// 손상(한쪽 파일만 있음·읽기 실패)이면 기존 파일을 덮어쓰지 않고 이번 실행만 임시 CA를 쓴다.
    /// 저장 실패(caSaveError)는 기기 윈도우에 표시한다. ponytail: 손상으로 임시 CA를 쓰는 경우는 아직 UI에 알리지 않음.
    private static func loadOrCreateCA() -> (CertificateAuthority, String?) {
        do {
            if let ca = try CertificateAuthority.load(from: caDirectory) { return (ca, nil) }
            let ca = try CertificateAuthority.generate(commonName: defaultCommonName())
            do {
                try ca.save(to: caDirectory)
                return (ca, nil)
            } catch {
                return (ca, error.localizedDescription)
            }
        } catch {
            guard let ca = try? CertificateAuthority.generate() else { fatalError("CA 생성 실패: \(error)") }
            return (ca, nil)
        }
    }

    /// 새 루트 CA 이름. 팀원끼리 기기를 같이 쓸 때 구별되도록 호스트 이름을 넣는다.
    static func defaultCommonName() -> String {
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "Mac"
        return "Prog Root CA (\(host))"
    }

    /// 옛 CA 폴더를 백업으로 옮기고 새 CA로 서버를 다시 띄운다. 결과는 `infoMessage`, 실패는 `systemError`.
    /// 확인 alert는 호출하는 쪽이 띄운다. 키체인·기기의 옛 CA는 건드리지 않는다.
    func resetCertificateAuthority() async {
        let rotated: (ca: CertificateAuthority, backup: URL?)
        do {
            rotated = try CARotation.rotate(directory: Self.caDirectory, commonName: Self.defaultCommonName())
        } catch {
            systemError = String(localized: "CA를 초기화하지 못했습니다: \(error.localizedDescription)")
            return
        }
        certificateAuthority = rotated.ca
        await restartServer()   // startServer가 현재 certificateAuthority로 ProxyServer·CAProfileResponder를 새로 만든다
        await refreshMacCAInstalled()
        let backupNote = rotated.backup.map { String(localized: "이전 CA는 \($0.path)에 있습니다.") }
            ?? String(localized: "이전 CA 폴더는 없었습니다.")
        infoMessage = String(localized: "새 CA를 만들었습니다. \(backupNote) Mac·시뮬레이터·기기에 다시 설치하세요. 키체인의 이전 CA는 키체인 접근에서 지우세요.")
    }

    // MARK: - 서버

    func startServer() async {
        guard server == nil else { return }
        let server = ProxyServer(
            configuration: .init(port: settings.port, sslPolicy: settings.sslPolicy),
            certificateAuthority: certificateAuthority,
            interceptors: toolChain())
        self.server = server
        // events는 단일 소비자이고 끝나지 않는다 → stopServer에서 취소한다.
        consumer = Task { [weak self] in
            for await event in server.events { self?.handle(event) }
        }
        do {
            let port = try await server.start()
            guard self.server === server else { return }   // 기다리는 동안 stopServer가 불렸다
            serverState = .running(port: port)
        } catch {
            guard self.server === server else { return }
            if case ProxyServerError.portInUse(let p) = error {
                let owners = await PortOwner.listeners(onPort: p)
                guard self.server === server else { return }   // 조회 중 stopServer가 불렸다
                serverState = .failed(message: Self.portInUseMessage(port: p, owners: owners))
            } else {
                serverState = .failed(message: error.localizedDescription)
            }
            consumer?.cancel()
            consumer = nil
            self.server = nil
        }
    }

    private static func portInUseMessage(port p: Int, owners: [(name: String, pid: Int32)]) -> String {
        if let old = owners.first(where: { ["Prog", "EyeProxy"].contains(where: $0.name.hasPrefix) }) {
            return String(localized: "이전 Prog 인스턴스(\(String(old.pid)))가 아직 포트를 쓰고 있습니다 — 잠시 후 다시 시도하세요")
        }
        guard !owners.isEmpty else { return String(localized: "포트 \(String(p)) 사용 중 — Proxyman을 끄거나 설정에서 포트를 바꾸세요") }
        let names = owners.map { "\($0.name)(\($0.pid))" }.joined(separator: ", ")
        return String(localized: "\(names)이 포트 \(String(p))을 사용 중 — 그 앱을 끄거나 설정에서 포트를 바꾼 뒤 다시 시도하세요")
    }

    func stopServer() async {
        consumer?.cancel()
        consumer = nil
        let running = server
        server = nil
        serverState = .stopped
        await running?.stop()
    }

    /// 호출 순서대로 직렬화한다. 각 갱신은 실행 시점의 설정을 읽으므로 마지막 토글이 이긴다.
    /// 포트 변경 적용. Mac 캡처 중이었으면 시스템 프록시도 새 포트로 맞추고, 서버가 못 뜨면 되돌린다.
    /// 호출 순서대로 직렬화하고, 진행 중인 캡처 변경이 끝난 뒤의 상태를 읽는다.
    func restartServer() async {
        let previous = restartUpdate
        let update = Task {
            await previous?.value
            await captureUpdate?.value
            let wasCapturing = macCaptureEnabled
            await stopServer()
            await startServer()
            if case .failed(let message) = serverState { systemError = message }
            guard wasCapturing else { return }
            if case .running = serverState { await setMacCapture(true, force: true) } else { await setMacCapture(false) }
        }
        restartUpdate = update
        await update.value
    }

    /// 실제로 떠 있는 서버의 포트. 설정값(settings.port)은 재시작 전까지 적용되지 않을 수 있다.
    var runningPort: Int? { if case .running(let p) = serverState { p } else { nil } }

    /// SSL 프록싱 켜기/끄기. 툴바 자물쇠와 상태 막대 메뉴가 같이 쓴다.
    func setSSLEnabled(_ on: Bool) {
        settings.sslEnabled = on
        Task { await applySettingsToServer() }
    }

    /// 상태 막대 눈: 실행 중이면 기록 여부로 뜨고 감고, 멈춤·실패면 빈 눈 + 사선.
    /// 빨간 점은 손볼 일이 있을 때만 — 멈춘 Breakpoint, 서버 시작 실패, 규칙 파일 경고.
    var statusIcon: StatusIcon {
        let eyes: StatusIcon.Eyes = runningPort == nil ? .stopped : (settings.isRecording ? .open : .closed)
        var failed = false
        if case .failed = serverState { failed = true }
        return StatusIcon(eyes: eyes, needsAttention: !breakpoints.pending.isEmpty || failed || !rules.loadWarnings.isEmpty)
    }

    func applySettingsToServer() async {
        let previous = settingsUpdate
        let update = Task {
            await previous?.value
            await server?.update(sslPolicy: settings.sslPolicy)
            // 자동 복호화가 SSL Proxying 설정을 보므로 체인도 다시 만든다.
            await applyTools()
        }
        settingsUpdate = update
        await update.value
    }

    private func handle(_ event: FlowEvent) {
        let isNewFlow = if case .requestStarted = event { true } else { false }
        // 기록 중지 상태에서도 이미 보이는 요청의 응답·실패는 반영한다.
        if settings.isRecording || !isNewFlow { liveSession.apply(event) }
        devices.observe(event)
        if case .annotated(let id, .unrecorded) = event { processes.remove(id) }
        // 소켓 조회는 비동기로 하고, 결과가 오면 귀속만 기록한다. 실제로 세션에 반영된 흐름만.
        if case .requestStarted(let flow) = event, liveSession.number(flow.id) != nil,
           FlowFilter.sameDevice(flow.clientAddress, "127.0.0.1"), let port = flow.clientPort, let proxyPort = runningPort {
            let id = flow.id
            Task { [resolver, processes] in
                // 조회 중에 미기록(Allow List)으로 빠진 흐름은 귀속하지 않는다.
                guard let identity = await resolver.resolve(port: port, proxyPort: proxyPort), liveSession.number(id) != nil else { return }
                processes.set(identity, for: id)
                // Advanced ▸ Hide Unnecessary Apple Requests from iOS Simulators: Block List 숨김과 같은 `.hidden`(눈 토글로 보기).
                if settings.hideAppleSimulatorRequests,
                   SimulatorNoise.isAppleNoise(host: flow.request.host, clientIsSimulator: identity.simulator != nil) {
                    liveSession.apply(.annotated(id: id, .hidden))
                }
                // 기기 창을 열지 않아도 시뮬레이터 런타임(플랫폼 표기)을 알 수 있게 처음 보는 udid면 목록을 갱신한다.
                if let sim = identity.simulator, !bootedSimulators.contains(where: { $0.udid == sim.udid }) { await refreshSimulators() }
            }
        }
    }

    // MARK: - 동작

    func enableSSLProxying(for host: String) async {
        if !settings.sslPatterns.contains(host) { settings.sslPatterns.append(host) }
        settings.sslEnabled = true
        await applySettingsToServer()
    }

    /// HTTPS Response 안내의 "Enable all domains from <앱>": 그 앱(`ProcessIdentity.groupKey`)의 흐름이 쓴 모든 호스트를 넣는다.
    func enableSSLProxying(forHostsOfApp groupKey: String, in tab: SessionTab) async {
        var patterns = settings.sslPatterns
        for flow in tab.session.flows where tab.processes.attribution[flow.id]?.groupKey == groupKey && !patterns.contains(flow.request.host) {
            patterns.append(flow.request.host)
        }
        settings.sslPatterns = patterns
        settings.sslEnabled = true
        await applySettingsToServer()
    }

    // MARK: - 세션 파일

    /// 세션·HAR 파일을 새 파일 탭으로 읽는다(스펙 §4.3). 창은 부르는 쪽이 `openWindow(id: "main", value:)`로 연다.
    /// 이미 열린 파일이면 그 탭 창을 앞으로 내고 nil. 실패하면 `systemError`에 쓰고 nil — 탭을 만들지 않는다.
    func open(_ url: URL) async -> UUID? {
        if bringOpenTab(for: url) { return nil }
        let session = SessionStore()
        let processes = ProcessRegistry()
        do {
            if url.pathExtension.lowercased() == "har" {
                try await importHAR(from: url, into: session)
            } else {
                let loaded = try await Task.detached { try SessionDocument.load(from: url) }.value
                session.replace(flows: loaded.flows, connectionLog: loaded.connectionLog, comments: loaded.comments,
                                highlights: loaded.highlights, numbers: loaded.numbers)
                processes.replace(loaded.processes)
            }
        } catch {
            systemError = if case FlowImportError.invalidHAR(let reason) = error {
                String(localized: "HAR 파일을 열지 못했습니다: \(reason)")
            } else {
                String(localized: "세션을 열지 못했습니다: \(error.localizedDescription)")
            }
            refreshRecent()   // 사라진 파일이면 목록에서 빠진다
            return nil
        }
        // 읽는 동안 같은 파일이 열렸으면(연달아 더블클릭) 그 탭으로.
        if bringOpenTab(for: url) { return nil }
        let tab = makeTab(fileURL: url, session: session, processes: processes, restoreSavedRules: false)
        noteRecent(url)
        return tab.id
    }

    private func bringOpenTab(for url: URL) -> Bool {
        let url = url.standardizedFileURL
        guard let tab = tabs.values.first(where: { $0.fileURL?.standardizedFileURL == url }) else { return false }
        tab.window?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Open…·Open Recent·끌어다 놓기: 열어서 새 탭 창을 띄운다. 창이 하나도 없으면 오류 알림을 띄울 창을 연다.
    func open(_ urls: [URL], openWindow: OpenWindowAction) async {
        for url in urls {
            if let id = await open(url) { openWindow(id: "main", value: id) }
        }
        if systemError != nil, tabs.isEmpty { showMainWindow(openWindow: openWindow) }
    }

    /// File ▸ Open… ⌘O.
    func openSession(openWindow: OpenWindowAction) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.sessionType] + Self.harTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await open([url], openWindow: openWindow)
    }

    // MARK: - 최근 파일 (File ▸ Open Recent)

    /// macOS 최근 문서 목록. 개별 삭제 API가 없어 다시 계산할 때 사라진 파일을 거른다.
    private(set) var recentURLs: [URL] = []

    private static func currentRecent() -> [URL] {
        NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func refreshRecent() { recentURLs = Self.currentRecent() }

    func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecent()
    }

    func clearRecent() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecent()
    }

    /// Info.plist의 UTExportedTypeDeclarations와 일치해야 한다.
    nonisolated static let sessionType = UTType(exportedAs: "com.tv.eyeproxy.session", conformingTo: .package)

    var simulatorRuntimes: [String: String] {
        Dictionary(bootedSimulators.map { ($0.udid, $0.runtime) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - 온보딩

    /// 호출 순서대로 직렬화한다(종료 경로가 진행 중인 켜기·끄기를 기다릴 수 있게).
    /// force: 이미 켜져 있어도 현재 포트로 다시 적용한다(포트 변경 후 재시작).
    func setMacCapture(_ on: Bool, force: Bool = false) async {
        let previous = captureUpdate
        let update = Task {
            await previous?.value
            await applyMacCapture(on, force: force)
            await refreshEffectiveProxyWarning()
        }
        captureUpdate = update
        await update.value
    }

    private func applyMacCapture(_ on: Bool, force: Bool) async {
        if on && quitting { return }
        // 끄기는 캡처 중이 아니어도 백업이나 VPN 복사본이 남아 있으면 복원한다(유지 후 실패·비정상 종료 잔여).
        // 서버가 떠 있지 않거나 설정 포트가 아직 적용 전이면 죽은 포트를 가리키게 된다 → 실제 실행 포트로만 켠다.
        let runningPort = self.runningPort
        if on, runningPort == nil {
            systemError = String(localized: "서버가 실행 중이 아니어서 시스템 프록시를 켤 수 없습니다")
            return
        }
        let needed = on ? (force || !macCaptureEnabled)
                        : (macCaptureEnabled || systemProxy.pendingRestore() != nil || effectiveProxyLeftover)
        guard needed else { return }
        macCaptureBusy = true
        defer {
            macCaptureBusy = false
            systemProxyBackupExists = systemProxy.pendingRestore() != nil
        }
        do {
            if on {
                try await systemProxy.enable(host: "127.0.0.1", port: runningPort ?? settings.port, bypass: settings.bypassHosts)
                capturePort = runningPort
            } else {
                try await systemProxy.disable(ownPort: capturePort ?? runningPort ?? settings.port)
            }
            macCaptureEnabled = on
        } catch {
            // 켜기 실패(관리자 인증 취소 등): 일부만 적용됐을 수 있으니 백업으로 되돌린다. 백업 없으면 원본을 모르므로 건드리지 않는다.
            if on, systemProxy.pendingRestore() != nil { try? await systemProxy.disable(ownPort: capturePort ?? runningPort ?? settings.port) }
            // 백업이 남아 있으면 프록시는 아직 EyeProxy를 가리킨다. 복원에 성공했다면 꺼진 상태다.
            if on { macCaptureEnabled = systemProxy.pendingRestore() != nil }
            systemError = on ? String(localized: "시스템 프록시를 켜지 못했습니다: \(Self.describe(error))")
                             : String(localized: "시스템 프록시를 되돌리지 못했습니다: \(Self.describe(error))")
        }
    }

    /// 기기 윈도우가 열릴 때와 캡처 변경 뒤에 호출한다.
    func refreshEffectiveProxyWarning() async {
        let ours = await systemProxy.effectiveProxyIsOurs(ownPort: capturePort ?? runningPort ?? settings.port)
        effectiveProxyLeftover = ours && systemProxy.pendingRestore() == nil
        vpnPrimaryDetected = await systemProxy.primaryIsVPN()
    }

    /// 종료 전에 시스템 프록시를 되돌려야 하는가(캡처 중·변경 중·백업 잔여).
    var needsProxyCleanupOnQuit: Bool {
        macCaptureEnabled || macCaptureBusy || systemProxy.pendingRestore() != nil || effectiveProxyLeftover
    }

    func prepareForQuit() async {
        quitting = true
        await setMacCapture(false)   // 진행 중인 변경 뒤에 직렬화된다
        await stopServer()
    }

    /// General ▸ Auto Override System Proxy Settings at Launch: 실행에 한 번만(메인 창을 다시 열어도 다시 켜지 않는다)
    /// 서버가 뜬 뒤 "이 Mac 캡처"를 켠다. 이전 실행이 남긴 프록시 복원 알림이 떠 있으면 사용자 선택에 맡긴다.
    func autoOverrideSystemProxyAtLaunch() async {
        guard !didAutoOverride else { return }
        didAutoOverride = true
        guard settings.autoOverrideSystemProxy, pendingProxyRestore == nil, runningPort != nil else { return }
        await setMacCapture(true)
    }

    func restorePendingProxy() async {
        pendingProxyRestore = nil
        await setMacCapture(false)
    }

    /// "유지": 남은 프록시를 이번 실행의 캡처로 채택한다. 원본 백업은 그대로 두고 현재 포트로 다시 맞춘다.
    /// 서버가 떠 있지 않으면 채택하지 않는다(프록시가 죽은 포트를 가리켜 인터넷이 끊긴다) — 기기 화면에서 복원할 수 있다.
    func adoptPendingProxy() async {
        pendingProxyRestore = nil
        guard case .running = serverState else { return }
        await setMacCapture(true)
    }

    /// 사용자에게 보일 오류 문구. 관리자 인증 취소(osascript -128)는 따로 알린다.
    static func describe(_ error: Error) -> String {
        let text = switch error {
        case SystemProxyError.commandFailed(let s), MacKeychainError.installFailed(let s), SimulatorsError.failed(let s),
             CertificateExportError.openSSL(let s): s
        case CertificateExportError.openSSLMissing: String(localized: "/usr/bin/openssl을 실행할 수 없습니다")
        case SystemProxyError.noActiveService: String(localized: "활성 네트워크 서비스를 찾지 못했습니다")
        case SystemProxyError.vpnProxyLeftover(let service):
            String(localized: "VPN 서비스(\(service))에 Prog 프록시가 남아 있습니다 — VPN을 재연결하세요")
        case SystemProxyError.vpnMirrorFailed(let service):
            String(localized: "VPN 서비스(\(service))에 Prog 프록시를 적용하지 못했습니다")
        default: error.localizedDescription
        }
        if text.contains("-128") || text.localizedCaseInsensitiveContains("canceled") || text.localizedCaseInsensitiveContains("cancelled") {
            return String(localized: "관리자 인증이 취소되었습니다")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 실행 중인 CA의 PEM. 디스크 CA와 다를 수 있으므로(손상 시 임시 CA) 메모리 CA를 임시 파일로 쓴다.
    private func caPEMFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "eyeproxy-ca.pem")
        try Data(certificateAuthority.certificatePEM.utf8).write(to: url, options: .atomic)
        return url
    }

    func refreshMacCAInstalled() async {
        guard let pem = try? caPEMFile() else { macCAInstalled = false; return }
        macCAInstalled = await MacKeychain.isInstalled(pemURL: pem)
    }

    func installCAOnMac() async throws {
        try await MacKeychain.installTrustedRoot(pemURL: caPEMFile())
        await refreshMacCAInstalled()
    }

    /// 실패(Xcode 없음 등)는 빈 목록으로 보인다.
    func refreshSimulators() async {
        bootedSimulators = ((try? await Simulators.listBooted()) ?? []).sorted { ($0.runtime, $0.name) < ($1.runtime, $1.name) }
    }

    func installCA(toSimulator udid: String) async throws {
        try await Simulators.installRootCert(udid: udid, pemURL: caPEMFile())
    }

    /// 평문 비밀번호 경고는 호출 전에 뷰가 띄운다. 비밀번호는 파일에만 들어가고 앱은 보관하지 않는다.
    /// 저장했으면 true.
    @discardableResult
    func saveWiFiProfile(ssid: String, security: WiFiSecurity, password: String?, proxyHost: String) async -> Bool {
        let panel = NSSavePanel()
        let safeName = ssid.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "Prog-\(safeName).mobileconfig"
        panel.allowedContentTypes = [.init(filenameExtension: "mobileconfig") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let data = MobileConfig.wifiProxyProfile(ssid: ssid, security: security, password: security == .none ? nil : password,
                                                 proxyHost: proxyHost, proxyPort: runningPort ?? settings.port)
        // 비밀번호가 평문으로 들어가므로 처음부터 0600으로 만든다(덮어쓰기면 기존 파일을 지우고 새로 만든다).
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            systemError = String(localized: "프로필을 저장하지 못했습니다: \(url.path)")
            return false
        }
        return true
    }
}

/// 관찰한 입력이 바뀌면 다시 계산하되, 연달아 바뀌면(요청이 쏟아질 때) `interval`마다 한 번으로 묶는다.
/// `now()`는 바로 계산한다(사용자 조작). 계산 중 읽은 관찰 값이 다음 변경 감지 대상이 된다.
@MainActor final class ThrottledRefresh {
    private let interval: Duration
    private let compute: @MainActor () -> Void
    private var pending: Task<Void, Never>?
    private var lastRun = ContinuousClock.now
    private var generation = 0

    init(interval: Duration = .milliseconds(250), _ compute: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.compute = compute
    }

    func now() {
        pending?.cancel()
        pending = nil
        generation += 1
        let g = generation
        withObservationTracking { compute() } onChange: { [weak self] in
            Task { @MainActor in self?.changed(g) }
        }
        // 계산이 끝난 뒤부터 잰다 — 한 번 계산이 interval보다 길어도 다음 계산 전에 늘 interval만큼 쉰다.
        // ponytail: 트래픽 중 갱신 상한은 1/(계산 시간 + 250 ms); 수만 건에서 더 필요하면 증분 갱신으로.
        lastRun = .now
    }

    /// 그사이 `now()`로 이미 다시 계산했으면(generation이 다름) 무시한다.
    private func changed(_ g: Int) {
        guard g == generation, pending == nil else { return }
        let wait = lastRun + interval - .now
        pending = Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return }
            self?.now()
        }
    }
}
