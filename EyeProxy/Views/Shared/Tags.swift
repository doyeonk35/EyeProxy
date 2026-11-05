import EyeProxyCore
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
}

private struct Capsuled: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct MethodTag: View {
    let method: String

    var body: some View {
        Text(method.uppercased()).modifier(Capsuled(color: FlowColors.method(method)))
    }
}

struct StatusTag: View {
    let flow: Flow

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
        .modifier(Capsuled(color: FlowColors.status(flow)))
    }
}
