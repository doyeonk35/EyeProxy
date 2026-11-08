import SwiftUI

enum CertificateSection: String, CaseIterable, Identifiable {
    case mac, simulators, iosDevices, tvWatch, android, developments, exportReset, connectedDevices

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .mac: "이 Mac"
        case .simulators: "iOS 시뮬레이터"
        case .iosDevices: "iPhone·iPad"
        case .tvWatch: "Apple TV·Apple Watch"
        case .android: "Android"
        case .developments: "개발 환경"
        case .exportReset: "내보내기·초기화"
        case .connectedDevices: "연결된 기기"
        }
    }

    var systemImage: String {
        switch self {
        case .mac: "laptopcomputer"
        case .simulators: "apps.iphone"
        case .iosDevices: "iphone"
        case .tvWatch: "appletv"
        case .android: "smartphone"
        case .developments: "terminal"
        case .exportReset: "square.and.arrow.up"
        case .connectedDevices: "dot.radiowaves.left.and.right"
        }
    }
}

/// 왼쪽 섹션 목록 + 오른쪽 내용. 메뉴는 `model.certificateSection`을 바꾼 뒤 이 창을 연다.
struct CertificateWindow: View {
    @Environment(AppModel.self) private var model
    @State private var installedSimulators: Set<String> = []

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(CertificateSection.allCases, selection: $model.certificateSection) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detail
                // 오류가 먼저, 안내는 오류를 닫은 뒤에 뜬다.
                .alert("안내", isPresented: Binding(get: { model.systemError == nil && model.infoMessage != nil },
                                                  set: { if !$0 { model.infoMessage = nil } })) {
                    Button("확인", role: .cancel) { model.infoMessage = nil }
                } message: {
                    Text(model.infoMessage ?? "")
                }
        }
        .onAppear { model.devicesWindowOpen = true }
        .onDisappear { model.devicesWindowOpen = false }
        .systemErrorAlert(model, presenting: true)
        // 초기화로 CA가 바뀌면 시뮬레이터에 다시 설치해야 한다.
        .onChange(of: model.certificateAuthority.sha256Fingerprint) { installedSimulators = [] }
        .task {
            await model.refreshMacCAInstalled()
            await model.refreshEffectiveProxyWarning()
            await model.refreshSimulators()
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.certificateSection {
        case .mac: form { MacSection() }
        case .simulators: form { SimulatorSection(installedSimulators: $installedSimulators) }
        case .iosDevices: form { IOSDevicesSection() }
        case .tvWatch: form { TVWatchSection() }
        case .android: form { AndroidSection() }
        case .developments: ContentUnavailableView("준비 중", systemImage: "hammer")
        case .exportReset: form { ExportResetSection() }
        case .connectedDevices: form { ConnectedDevicesSection(); ConnectionLogSection() }
        }
    }

    private func form(@ViewBuilder _ content: () -> some View) -> some View {
        Form(content: content).formStyle(.grouped)
    }
}
