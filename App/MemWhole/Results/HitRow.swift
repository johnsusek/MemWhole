import MemWholeKit
import SwiftUI

struct HitRow: View {
    let hit: Hit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.oneLine(hit.title ?? hit.path)).font(.headline).lineLimit(1)
                Spacer()
                Text(date).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(highlighted(Format.oneLine(hit.snippet)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let project = hit.project {
                Text(Format.path(project)).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var date: String {
        Format.parse(hit.ts)?.formatted(date: .abbreviated, time: .omitted) ?? Format.date(hit.ts)
    }

    /// Bolds the text between FTS5 snippet markers.
    private func highlighted(_ snippet: String) -> AttributedString {
        Marks.attributed(snippet) { match, _ in
            match.inlinePresentationIntent = .stronglyEmphasized
            match.foregroundColor = .primary
        }
    }
}
