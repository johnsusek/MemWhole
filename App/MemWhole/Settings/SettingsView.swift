import MemWholeKit
import SwiftUI

/// Settings (⌘,): where the index comes from and where it lives.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Indexed Folder") {
                LabeledContent("Folder") {
                    Text(model.folderPath.map(Format.path) ?? "None")
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose…") { model.chooseFolderAndIndex() }
                    Button("Update Now") { model.reindex() }
                        .disabled(model.folderPath == nil || model.isIndexing)
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
