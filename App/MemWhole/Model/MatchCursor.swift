import SwiftUI

/// The open file's place among its matches, published so Find Next / Find Previous can step through them.
struct MatchCursor {
    let count: Int
    let current: Binding<Int>

    func step(_ delta: Int) {
        guard count > 0 else { return }
        current.wrappedValue = (current.wrappedValue + delta + count) % count
    }
}

extension FocusedValues {
    @Entry var matchCursor: MatchCursor?
}
