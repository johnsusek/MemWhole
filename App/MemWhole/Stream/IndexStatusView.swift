import MemWholeKit
import SwiftUI

/// Footer shown while indexing, with its progress.
struct IndexStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(model.progress)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .help(model.folderPath.map { "Indexing \(Format.path($0))" } ?? "No folder chosen")
        .accessibilityElement(children: .combine)
    }
}
