import AppKit
import EyeProxyKit
import SwiftUI

/// 개발 환경: 왼쪽 플랫폼 목록 + 오른쪽 단계 안내와 복사할 스니펫.
struct DevelopmentsSection: View {
    @Environment(AppModel.self) private var model

    private var guide: DevGuide {
        DevSnippets.guide(for: model.developmentPlatform,
                          pemPath: AppModel.caDirectory.appending(path: "ca.pem").path,
                          proxyHost: "127.0.0.1",
                          proxyPort: model.runningPort ?? model.settings.port)
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            List(DevPlatform.allCases, selection: $model.developmentPlatform) { platform in
                Text(verbatim: platform.title)
            }
            .frame(width: 180)
            Divider()
            detail
        }
    }

    private var detail: some View {
        let guide = guide
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: model.developmentPlatform.title).font(.title2.bold())
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        Text(verbatim: "\(index + 1). \(step)")
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                if !guide.snippet.isEmpty {
                    Text(verbatim: guide.snippet)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
                    Button("복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(guide.snippet, forType: .string)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
