import EyeProxyCore
import EyeProxyKit
import SwiftUI

enum FlowColors {
    static func method(_ m: String) -> Color {
        switch m.uppercased() {
        case "GET": Color("MethodGet")
        case "POST": Color("MethodPost")
        case "PUT", "PATCH": Color("MethodPut")
        case "DELETE": Color("MethodDelete")
        default: Color("MethodOther")
        }
    }

    static func status(_ flow: Flow) -> Color {
        if let status = flow.response?.status {
            return status >= 400 ? Color("StatusError") : status >= 300 ? Color("StatusRedirect") : Color("StatusSuccess")
        }
        return flow.error != nil ? Color("StatusError") : Color("StatusPending")
    }

    /// 목록 상태 점: 완료 초록·진행 주황·실패 빨강.
    static func state(_ state: FlowState) -> Color {
        switch state {
        case .completed: Color("StatusSuccess")
        case .active: Color("StatusRedirect")
        case .failed: Color("StatusError")
        }
    }
}

/// 칩 스타일. 선택된 행 위에서는 시스템 강조색(파랑)과 칩 색(GET 파랑 등)이 겹쳐 안 보이므로
/// 흰 글자 + 반투명 흰 배경으로 바꿔 어떤 강조색 위에서도 읽히게 한다.
struct Capsuled: ViewModifier {
    let color: Color
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(selected ? Color.white : color)
            .background(selected ? Color.white.opacity(0.28) : color.opacity(0.15), in: Capsule())
    }
}

struct MethodTag: View {
    let method: String
    var selected = false

    var body: some View {
        Text(method.uppercased()).modifier(Capsuled(color: FlowColors.method(method), selected: selected))
    }
}

struct StatusTag: View {
    let flow: Flow
    var selected = false

    var body: some View {
        Group {
            if let status = flow.response?.status {
                Text(String(status))
            } else if flow.error != nil {
                Text("오류")
            } else {
                Text(verbatim: "…")
            }
        }
        .modifier(Capsuled(color: FlowColors.status(flow), selected: selected))
    }
}

/// Edited 열 칩(Map Local 등 요청·응답을 바꾼 도구).
struct EditedTag: View {
    let mark: ToolMark
    var selected = false

    var body: some View {
        Text(mark.rawValue).modifier(Capsuled(color: Color("StatusRedirect"), selected: selected))
    }
}
