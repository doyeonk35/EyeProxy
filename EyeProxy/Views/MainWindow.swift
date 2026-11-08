import AppKit
import EyeProxyCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
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
        .toolbar { MainToolbar(model: model) }
        .searchable(text: $model.filter.text, placement: .toolbar, prompt: Text("URL·메서드·상태 검색"))
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
