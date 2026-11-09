import EyeProxyKit
import SwiftUI

/// 목록 위 한 줄 필터 바(스펙 §6). 묶음 안은 OR, 묶음 사이·검색어·사이드바와는 AND. 저장하지 않는다.
struct FilterBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip("All", selected: model.filter.isBarEmpty, help: "분류 필터 모두 해제") { model.filter.clearBar() }
                Divider().frame(height: 14)
                ForEach(FlowProtocol.allCases, id: \.self) { p in
                    chip(p.rawValue, selected: model.filter.protocols.contains(p), help: Self.help(p)) {
                        model.filter.protocols.formSymmetricDifference([p])
                    }
                }
                Divider().frame(height: 14)
                ForEach(ContentKind.allCases, id: \.self) { kind in
                    chip(kind.rawValue, selected: model.filter.contentKinds.contains(kind), help: Self.help(kind)) {
                        model.filter.contentKinds.formSymmetricDifference([kind])
                    }
                }
                Divider().frame(height: 14)
                ForEach(1...5, id: \.self) { c in
                    chip("\(c)xx", selected: model.filter.statusClasses.contains(c), help: "상태 코드 \(c)xx 응답만 보기") {
                        model.filter.statusClasses.formSymmetricDifference([c])
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(.bar)
    }

    private func chip(_ label: String, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(help)
    }

    private static func help(_ p: FlowProtocol) -> String {
        switch p {
        case .http: "https가 아닌 요청만 보기"
        case .https: "https 요청만 보기(복호화 안 한 터널 포함)"
        }
    }

    private static func help(_ kind: ContentKind) -> String {
        switch kind {
        case .json: "Content-Type이 json인 응답만 보기"
        case .form: "form-urlencoded·multipart 요청만 보기"
        case .xml: "Content-Type이 xml인 응답만 보기"
        case .js: "JavaScript 응답만 보기"
        case .css: "CSS(text/css) 응답만 보기"
        case .graphql: "GraphQL 요청만 보기(경로·Content-Type)"
        case .document: "html·텍스트·pdf·markdown·csv 응답만 보기"
        case .media: "이미지·영상·오디오·폰트·HLS 응답만 보기"
        case .other: "그 밖의 응답만 보기(octet-stream·터널 등)"
        }
    }
}
