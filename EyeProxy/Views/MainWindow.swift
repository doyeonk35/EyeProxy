import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if model.settings.layout == .classic {
                VSplitView {
                    FlowListView().frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                    FlowDetailView().frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                }
            } else {
                HSplitView {
                    FlowListView().frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    FlowDetailView().frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar { MainToolbar(model: model) }
        .searchable(text: $model.filter.text, placement: .toolbar, prompt: Text("URL·메서드·상태 검색"))
    }
}
