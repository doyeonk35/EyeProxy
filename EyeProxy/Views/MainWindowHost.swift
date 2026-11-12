import AppKit
import SwiftUI

/// 메인 창을 macOS 기본 창 탭(`prog.main`)으로 묶고, 그 창의 key·가림·닫힘을 탭과 `AppModel`에 알린다(스펙 §4.1).
struct MainWindowHost: NSViewRepresentable {
    @Environment(AppModel.self) private var model
    let tab: SessionTab

    final class Hook: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    @MainActor final class Coordinator {
        private var observers: [NSObjectProtocol] = []

        func attach(_ window: NSWindow, model: AppModel, tab: SessionTab) {
            guard tab.window !== window else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            window.tabbingIdentifier = "prog.main"
            window.tabbingMode = .preferred
            // 창이 이미 떠서 저절로 탭으로 붙지 않았으면(⌘T·Open as New Tab) 앞 창의 탭으로 붙인다.
            if let front = model.activeTab?.window, front !== window, front.isVisible,
               !(front.tabbedWindows ?? []).contains(window) {
                front.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }
            tab.window = window
            if window.isKeyWindow { model.activeTab = tab }
            tab.isOnScreen = window.occlusionState.contains(.visible)
            // 탭 복원: 복원한 탭 창이 모두 붙으면 종료 때 앞이던 탭을 앞으로 낸다. 붙은 창이 key가 된 다음에 낸다.
            if model.restoredTabsAwaitingWindow.remove(tab.id) != nil, model.restoredTabsAwaitingWindow.isEmpty,
               let id = model.pendingKeyTabID {
                model.pendingKeyTabID = nil
                let front = model.tab(id)?.window
                Task { @MainActor in front?.makeKeyAndOrderFront(nil) }
            }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak model, weak tab] _ in
                    MainActor.assumeIsolated { if let tab { model?.activeTab = tab } }
                },
                center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak tab, weak window] _ in
                    MainActor.assumeIsolated {
                        if let window { tab?.isOnScreen = window.occlusionState.contains(.visible) }
                    }
                },
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak model, weak tab] _ in
                    MainActor.assumeIsolated {
                        if let tab { model?.closeTab(tab.id) }
                        self?.observers.forEach(NotificationCenter.default.removeObserver)
                        self?.observers = []
                    }
                },
            ]
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Hook {
        let view = Hook()
        let (coordinator, model, tab) = (context.coordinator, model, tab)
        view.onWindow = { coordinator.attach($0, model: model, tab: tab) }
        return view
    }

    func updateNSView(_ view: Hook, context: Context) {}
}
