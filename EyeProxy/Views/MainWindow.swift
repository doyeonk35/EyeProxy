import AppKit
import EyeProxyCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var searchFindID = UUID()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            split
            Divider()
            BottomBar()
        }
        .toolbar { MainToolbar(model: model) }
        // Advanced ▸ Stay On Top: 켤 때·끌 때, 그리고 창이 새로 열려 앞으로 올 때마다 Prog 창 전체에 맞춘다.
        .onChange(of: model.settings.stayOnTop, initial: true) { _, on in StayOnTop.apply(on) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            StayOnTop.apply(model.settings.stayOnTop)
        }
        .focusedSceneValue(\.flowSearch, DetailFind(id: searchFindID, open: { model.showFilterBar() }))
        .sheet(isPresented: Binding(get: { model.commentingFlowID != nil }, set: { if !$0 { model.commentingFlowID = nil } })) {
            if let id = model.commentingFlowID { CommentSheet(id: id) }
        }
        // 새로 멈춘 건이 생기면 Breakpoint 창을 앞으로(스펙 §5.1). 관찰은 앱 수준(AppModel.observeBreakpoints)이 한다.
        .onAppear { model.openBreakpointsWindow = { openWindow(id: "breakpoints") } }
        // 규칙 파일을 읽거나 저장하지 못했으면 알린다. 확인하면 경고를 지운다.
        .onChange(of: model.rules.loadWarnings.count, initial: true) { _, count in
            if count > 0 { model.showRuleWarnings = true }
        }
        .alert("규칙 파일 경고", isPresented: $model.showRuleWarnings) {
            Button("확인") { model.rules.clearWarnings() }
        } message: {
            Text(model.rules.loadWarnings.joined(separator: "\n"))
        }
    }

    private var split: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                FilterBarView()
                Divider()
                if model.isFilterBarVisible {
                    FilterRulesBar()
                    Divider()
                }
                if model.settings.layout == .classic {
                    VSplitView {
                        FlowListView().frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                        FlowDetailView().frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    }
                } else {
                    HSplitView {
                        FlowListView().frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                        FlowDetailView().frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

/// Flow ▸ Add/Edit Comment… 시트. 빈 문자열로 저장하면 코멘트를 지운다.
private struct CommentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: FlowID
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.session.comments[id] == nil ? "Add Comment" : "Edit Comment").font(.headline)
            if let flow = model.session.flow(id) {
                Text(flow.request.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            TextField("코멘트", text: $text, axis: .vertical)
                .lineLimit(4...10)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    model.session.setComment(text.trimmingCharacters(in: .whitespacesAndNewlines), for: id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { text = model.session.comments[id] ?? "" }
    }
}

/// Advanced ▸ Stay On Top: Prog의 일반 창(메인·Breakpoint·Compose·도구·Certificate·Settings)을 모두 floating으로 —
/// 메인 창만 올리면 새로 멈춘 Breakpoint 창이나 설정 창이 그 뒤에 가린다. 패널(저장·알림)·시트·메뉴 막대 창은
/// 자기 수준을 스스로 정하므로 건드리지 않는다(제목 막대가 있는 NSWindow이고 수준이 normal·floating인 것만).
enum StayOnTop {
    @MainActor static func apply(_ on: Bool) {
        let level: NSWindow.Level = on ? .floating : .normal
        DispatchQueue.main.async {
            for w in NSApp.windows where !(w is NSPanel) && w.sheetParent == nil && w.styleMask.contains(.titled)
                && (w.level == .normal || w.level == .floating) {
                w.level = level
            }
        }
    }
}
