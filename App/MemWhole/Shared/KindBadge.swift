import SwiftUI

/// What kind of file a result comes from: a transcript, or a doc kind.
struct KindBadge: View {
    let kind: String

    var body: some View {
        Badge(label: kind.replacingOccurrences(of: "-", with: " "), color: color)
    }

    private var color: Color {
        switch kind {
        case "subagent": .purple
        case "session": .blue
        case "memory": .orange
        case "skill": .green
        case "prompt": .teal
        case "snapshot": .gray
        case "task": .pink
        case "rules": .indigo
        case "config": .brown
        case "plugin-doc": .mint
        case "plugin-manifest": .cyan
        case "changelog": .yellow
        default: .secondary
        }
    }
}
