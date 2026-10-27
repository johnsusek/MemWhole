import MemWholeKit
import SwiftUI

struct HitRow: View {
    let hit: Hit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                KindBadge(kind: hit.type == "doc" ? hit.role : hit.sidechain ? "subagent" : "session")
                Spacer()
                if hit.matches > 1 {
                    Text("\(hit.matches) matches").font(.caption).foregroundStyle(.secondary)
                }
                Text(Format.date(hit.ts)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let title = hit.title, !title.isBlank {
                Text(Format.oneLine(title)).font(.headline).lineLimit(1)
            }
            Text(highlighted(Format.oneLine(hit.snippet)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let project = hit.project {
                Text(Format.path(project)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Bolds the text between FTS5 snippet markers.
    private func highlighted(_ snippet: String) -> AttributedString {
        Marks.attributed(snippet) { match, _ in
            match.inlinePresentationIntent = .stronglyEmphasized
            match.foregroundColor = .primary
        }
    }
}
