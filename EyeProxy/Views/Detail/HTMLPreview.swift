import SwiftUI
import WebKit

/// 네트워크·스크립트 없이 HTML만 렌더링한다. (본문은 한 번만 로드: BodyView가 flow마다 새로 만들어진다)
struct HTMLPreview: NSViewRepresentable {
    let html: String

    private static let blockAll = #"[{"trigger":{"url-filter":"^(https?|ftp|wss?)://"},"action":{"type":"block"}}]"#

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        let html = html
        // 하위 리소스(img/css) 네트워크 로딩도 룰 리스트로 차단한 뒤에 로드한다.
        Task { @MainActor in
            if let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "eyeproxy.block", encodedContentRuleList: Self.blockAll) {
                config.userContentController.add(list)
            }
            web.loadHTMLString(html, baseURL: nil)
        }
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}
