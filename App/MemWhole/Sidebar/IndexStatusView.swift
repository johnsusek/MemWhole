import MemWholeKit
import SwiftUI

/// Sidebar footer: indexing progress, or what the index holds.
struct IndexStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.isIndexing {
                ProgressView().controlSize(.small)
            }
            Text(model.isIndexing ? model.progress : model.status)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help(model.folderPath.map { "Indexing \(Format.path($0))" } ?? "No folder chosen")
        .accessibilityElement(children: .combine)
    }
}
