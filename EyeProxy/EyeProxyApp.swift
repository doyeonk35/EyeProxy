import SwiftUI

@main struct EyeProxyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("EyeProxy", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .task { await model.startServer() }
        }
        .commands {
            // 툴바 버튼의 keyboardShortcut은 동작하지 않아 메뉴 막대에 둔다.
            CommandMenu("프록시") {
                Toggle("기록", isOn: Bindable(model.settings).isRecording)
                    .keyboardShortcut("r")
                Button("목록 지우기") { model.clear() }
                    .keyboardShortcut("k")
            }
        }
    }
}
