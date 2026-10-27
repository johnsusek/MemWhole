import MemWholeKit
import SwiftUI

struct MessageView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let message: Store.Message
    let marked: String?
    /// Order of the current match within this message, when it holds the current match.
    let currentMatch: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoleBadge(role: message.role)
                if message.sidechain {
                    Text("agent").font(.caption2).foregroundStyle(.secondary)
                }
                Text(Format.date(message.ts)).font(.caption).foregroundStyle(.secondary)
            }
            Group {
                if let marked {
                    Text(highlightedMatches(marked, current: currentMatch))
                } else {
                    Text(message.text)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(background, in: .rect(cornerRadius: 8))
        .overlay {
            if currentMatch != nil {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .findHighlightColor), lineWidth: 1.5)
            } else if contrast == .increased {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.separator)
            }
        }
    }

    private var background: AnyShapeStyle {
        message.role == "user" ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(.quinary)
    }
}
