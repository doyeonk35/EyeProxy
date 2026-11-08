import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// Breakpoint Templates 창(스펙 §5.1): 왼쪽 Request/Response Templates 트리, 오른쪽 편집.
/// 편집은 `draft`에 두고 다른 템플릿을 고르거나 창을 닫거나 Save(⌘S)할 때 저장한다.
struct BreakpointTemplatesWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var draft: BreakpointTemplate?
    @State private var confirmDelete = false
    @State private var collapsed = Set<BreakpointPhase>()

    private var templates: [BreakpointTemplate] { model.rules.breakpointTemplates }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(selection: $selection) {
                    Section("Breakpoint Templates") {
                        folder("Request Templates", kind: .request)
                        folder("Response Templates", kind: .response)
                    }
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                Group {
                    if draft != nil {
                        editor
                    } else {
                        VStack(spacing: 6) {
                            Text("No Template Selection").font(.title3)
                            Text(verbatim: "⌘N: Add new Request").foregroundStyle(.secondary)
                            Text(verbatim: "⇧⌘N: Add new Response").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 8) {
                Menu {
                    Button("New Request Template") { add(.request) }
                    Button("New Response Template") { add(.response) }
                } label: { Image(systemName: "plus") }
                .menuIndicator(.hidden)
                .fixedSize()
                Button { confirmDelete = true } label: { Image(systemName: "minus") }
                    .disabled(draft == nil)
                    .help("Delete")
                if let url = URL(string: "https://docs.proxyman.com/advanced-features/breakpoint") { HelpLink(destination: url) }
                Spacer()
                Menu("More") {
                    Button("Import…") {}.disabled(true)
                    Button("Export…") {}.disabled(true)
                }
                .fixedSize()
            }
            .padding(8)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background {
            Group {
                Button("New Request Template") { add(.request) }.keyboardShortcut("n")
                Button("New Response Template") { add(.response) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Save") { commit() }.keyboardShortcut("s")
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: selection) { _, id in
            commit()
            draft = templates.first { $0.id == id }
        }
        .onDisappear(perform: commit)
        .confirmationDialog("선택한 템플릿을 삭제할까요? 되돌릴 수 없습니다.", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive, action: deleteSelection)
            Button("취소", role: .cancel) {}
        }
    }

    private func folder(_ title: LocalizedStringKey, kind: BreakpointPhase) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(kind) },
                                            set: { if $0 { collapsed.remove(kind) } else { collapsed.insert(kind) } })) {
            ForEach(templates.filter { $0.kind == kind }) { t in
                Label(t.name, systemImage: "doc.text").tag(t.id)
            }
        } label: {
            Label(title, systemImage: "folder")
        }
    }

    // MARK: - 편집

    @ViewBuilder private var editor: some View {
        if let current = draft {
            let d = Binding(get: { draft ?? current }, set: { draft = $0 })
            VStack(alignment: .leading, spacing: 10) {
                Form {
                    TextField("Name", text: d.name)
                    if current.kind == .request {
                        TextField("Method", text: Binding(get: { d.wrappedValue.method ?? "" }, set: { d.wrappedValue.method = $0.isEmpty ? nil : $0.uppercased() }),
                                  prompt: Text(verbatim: "GET"))
                        TextField("URL", text: Binding(get: { d.wrappedValue.url ?? "" }, set: { d.wrappedValue.url = $0.isEmpty ? nil : $0 }),
                                  prompt: Text(verbatim: "https://api.example.com/v1/items"))
                        Text("빈 칸은 멈춘 요청의 원래 값을 그대로 씁니다").font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("Status Code", text: Binding(
                            get: { d.wrappedValue.status.map(String.init) ?? "" },
                            set: { t in
                                let digits = t.filter(\.isNumber)
                                if digits.isEmpty { d.wrappedValue.status = nil } else if let s = Int(digits), (100...999).contains(s) { d.wrappedValue.status = s }
                            }), prompt: Text(verbatim: "200"))
                    }
                }
                .formStyle(.grouped)
                .frame(maxHeight: 190)
                Text("Headers").font(.headline).padding(.horizontal)
                Text("적용하면 멈춘 건의 헤더를 이 목록으로 통째로 바꿉니다").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                PairEditor(rows: d.headers, keyPrompt: "New Key…", valuePrompt: "New Value…")
                    .padding(.horizontal)
                HStack {
                    Spacer()
                    Button("Save") { commit() }
                        .disabled(draft == templates.first { $0.id == current.id })
                }
                .padding([.horizontal, .bottom])
            }
        }
    }

    // MARK: - 데이터

    private func commit() {
        guard var d = draft, let i = templates.firstIndex(where: { $0.id == d.id }) else { return }
        d.headers.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if d.name.trimmingCharacters(in: .whitespaces).isEmpty { d.name = templates[i].name }
        if templates[i] != d { model.rules.breakpointTemplates[i] = d }
    }

    private func add(_ kind: BreakpointPhase) {
        commit()
        let t = BreakpointTemplate(name: kind == .request ? "New Request" : "New Response", kind: kind)
        model.rules.breakpointTemplates.append(t)
        selection = t.id
    }

    private func deleteSelection() {
        guard let id = draft?.id else { return }
        draft = nil
        model.rules.breakpointTemplates.removeAll { $0.id == id }
        selection = nil
    }
}
