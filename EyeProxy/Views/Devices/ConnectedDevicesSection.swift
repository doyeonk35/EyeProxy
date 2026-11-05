import EyeProxyKit
import SwiftUI

struct ConnectedDevicesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("연결된 기기") {
            if model.devices.devices.isEmpty {
                Text("아직 트래픽을 보낸 기기가 없습니다").foregroundStyle(.secondary)
            }
            ForEach(model.devices.devices) { device in
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        TextField("이름", text: nameBinding(device), prompt: Text(device.displayName))
                            .labelsHidden()
                        Text(device.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Picker("종류", selection: kindBinding(device)) {
                        ForEach(DeviceKind.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    VStack(alignment: .trailing) {
                        Text(device.lastSeen, format: .relative(presentation: .named))
                        Text("요청 \(device.flowCount) · 복호화 \(device.decryptedCount) · TLS 실패 \(device.tlsFailureCount)")
                            .foregroundStyle(device.tlsFailureCount > 0 ? .orange : .secondary)
                    }
                    .font(.caption)
                    .frame(minWidth: 200, alignment: .trailing)
                }
            }
        }
    }

    private func nameBinding(_ device: Device) -> Binding<String> {
        Binding(get: { device.name ?? "" }, set: { update(device, name: $0.isEmpty ? nil : $0, kind: device.kind) })
    }

    private func kindBinding(_ device: Device) -> Binding<DeviceKind> {
        Binding(get: { device.kind }, set: { update(device, name: device.name, kind: $0) })
    }

    private func update(_ device: Device, name: String?, kind: DeviceKind) {
        model.devices.rename(device.address, name: name, kind: kind)
        try? model.devices.save()   // 실패해도 메모리에는 남고 종료 시 다시 저장한다
    }

    static func label(_ kind: DeviceKind) -> String {
        switch kind {
        case .thisMac: String(localized: "이 Mac")
        case .appleTV: "Apple TV"
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .unknown: String(localized: "알 수 없음")
        }
    }
}

struct ConnectionLogSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("연결 로그 (최근 50건)") {
            let entries = model.session.connectionLog.suffix(50).reversed()
            if entries.isEmpty {
                Text("기록 없음").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.date, format: .dateTime.hour().minute().second()).monospacedDigit()
                    Text(entry.clientAddress).frame(width: 110, alignment: .leading)
                    Text(verbatim: "\(entry.host):\(entry.port)").frame(minWidth: 160, alignment: .leading)
                    Text(entry.message).foregroundStyle(entry.message.contains("신뢰") ? .orange : .primary)
                }
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
            }
        }
    }
}
