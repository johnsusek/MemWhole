import SwiftUI

/// Accessory bar above a file for stepping through its matches. Find Next / Find Previous (⌘G, ⇧⌘G) do the same.
struct MatchBar: View {
    let cursor: MatchCursor

    var body: some View {
        HStack(spacing: 8) {
            Text("\(cursor.current.wrappedValue + 1) of \(cursor.count) \(cursor.count == 1 ? "match" : "matches")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            ControlGroup {
                Button("Previous Match", systemImage: "chevron.up") { cursor.step(-1) }
                    .help("Previous match (⇧⌘G)")
                Button("Next Match", systemImage: "chevron.down") { cursor.step(1) }
                    .help("Next match (⌘G)")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .fixedSize()
            .disabled(cursor.count < 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
