import SwiftUI

/// Source list of what a search can cover, with the index's status underneath.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.scopeSelection) {
            Section("Library") {
                ForEach(Scope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage)
                        .badge(model.counts.map { scope.count(in: $0) } ?? 0)
                        .tag(scope)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { IndexStatusView() }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
    }
}
