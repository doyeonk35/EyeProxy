import EyeProxyKit
import SwiftUI

/// 부팅된 iOS 시뮬레이터마다 한 번 클릭으로 CA 설치.
struct SimulatorSection: View {
    @Environment(AppModel.self) private var model
    /// 섹션을 오가도 "설치됨"이 남도록 창이 갖고 있다.
    @Binding var installedSimulators: Set<String>
    @State private var busy = false

    var body: some View {
        Section {
            if model.bootedSimulators.isEmpty {
                Text("부팅된 시뮬레이터가 없습니다").foregroundStyle(.secondary)
            }
            ForEach(model.bootedSimulators) { sim in
                LabeledContent {
                    if installedSimulators.contains(sim.udid) {
                        Label("설치됨", systemImage: "checkmark").foregroundStyle(.green)
                    } else {
                        Button("CA 설치") {
                            model.runCAInstall(busy: $busy) {
                                try await model.installCA(toSimulator: sim.udid)
                                installedSimulators.insert(sim.udid)
                            }
                        }
                        .disabled(busy)
                        .help("이 시뮬레이터에 Prog CA 설치")
                    }
                } label: {
                    Text(sim.name)
                    Text(sim.runtime)
                }
            }
        } header: {
            HStack {
                Text("시뮬레이터")
                Spacer()
                Button("새로고침", systemImage: "arrow.clockwise") { Task { await model.refreshSimulators() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("부팅된 시뮬레이터 목록 새로고침")
            }
        } footer: {
            Text("설치 후 앱을 다시 실행하세요")
        }
    }
}
