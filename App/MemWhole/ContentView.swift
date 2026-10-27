import SwiftUI

/// Source list of scopes, the results for the current search, and the selected result in full.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
        } content: {
            ResultsView()
        } detail: {
            DetailView()
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search sessions, memory, skills")
        .searchFocusedIfAvailable($isSearchFocused)
        .onChange(of: model.isSearchFocused) { _, focused in
            isSearchFocused = focused
        }
        .onChange(of: isSearchFocused) { _, focused in
            model.isSearchFocused = focused
        }
    }
}
