import SwiftUI

extension View {
    /// Binds the search field's focus where the OS supports it (macOS 15 and later).
    @ViewBuilder
    func searchFocusedIfAvailable(_ isFocused: FocusState<Bool>.Binding) -> some View {
        if #available(macOS 15, *) {
            searchFocused(isFocused)
        } else {
            self
        }
    }
}
