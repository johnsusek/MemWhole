import SwiftUI

/// Who wrote a transcript message.
struct RoleBadge: View {
    let role: String

    var body: some View {
        switch role {
        case "user": Badge(label: "you", color: .blue)
        case "assistant": Badge(label: "claude", color: .purple)
        default: Badge(label: role, color: .gray)
        }
    }
}
