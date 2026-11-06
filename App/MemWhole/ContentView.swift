import SwiftUI

/// The stream of notes under the window's search field.
struct ContentView: View {
  @Environment(AppModel.self) private var model
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    @Bindable var model = model

    StreamView()
      .searchable(text: $model.query, placement: .toolbar, prompt: "Search memories")
      .searchFocused($isSearchFocused)
      .toolbar(id: "main") { MainToolbar(model: model) }
      .onChange(of: model.isSearchFocused) { _, focused in isSearchFocused = focused }
      .onChange(of: isSearchFocused) { _, focused in model.isSearchFocused = focused }
  }
}
