import SwiftUI

/// Colored capsule label.
struct Badge: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(contrast == .increased ? 0.3 : 0.15), in: Capsule())
            .foregroundStyle(contrast == .increased ? .primary : color)
    }
}
