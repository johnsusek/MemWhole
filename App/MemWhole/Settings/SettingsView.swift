import MemWholeKit
import SwiftUI

/// Settings (⌘,): where the index comes from and where it lives.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Sources") {
                ForEach(MemorySource.allCases, id: \.self) { source in
                    LabeledContent(source.title) {
                        Text(Format.path(source.root.path))
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Update Now") { model.reindex() }
                        .disabled(model.isIndexing)
                    Spacer()
                    if model.isIndexing { ProgressView().controlSize(.small) }
                }
            }
            Section("Index") {
                LabeledContent("Contents", value: model.status)
                LabeledContent("Location") {
                    Text(Format.path(model.databasePath))
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button("Show in Finder") { model.reveal(URL(fileURLWithPath: model.databasePath)) }
                    .disabled(!model.hasIndex)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
