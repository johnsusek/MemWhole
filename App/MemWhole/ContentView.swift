import MemWholeKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(model.hits, selection: $model.selection) { hit in
                HitRow(hit: hit)
            }
            .overlay { emptyState }
            .safeAreaInset(edge: .bottom) { statusBar }
            .navigationSplitViewColumnWidth(min: 320, ideal: 400)
            .searchable(text: $model.query, placement: .sidebar, prompt: "Search sessions, memory, skills")
        } detail: {
            DetailView()
        }
        .toolbar {
            ToolbarItem {
                Picker("Scope", selection: $model.scope) {
                    ForEach(Scope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Limit results to one kind")
            }
            ToolbarItem {
                Picker("Sort", selection: $model.sort) {
                    Text("Newest First").tag(SearchSort.date)
                    Text("Best Match").tag(SearchSort.relevance)
                }
                .pickerStyle(.menu)
                .help("Order of results")
            }
            ToolbarItem {
                if model.isIndexing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update Index", systemImage: "arrow.clockwise") {
                        model.folderPath == nil ? model.chooseFolderAndIndex() : model.reindex()
                    }
                    .help(model.folderPath.map { "Re-index \(Format.path($0))" } ?? "Choose a folder to index")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.hasIndex && !model.isIndexing {
            ContentUnavailableView {
                Label("No Index Yet", systemImage: "tray")
            } description: {
                Text("Choose your ~/.claude folder, or a copy of it, to build a search index.")
            } actions: {
                Button("Choose Folder…") { model.chooseFolderAndIndex() }
            }
        } else if let error = model.errorMessage {
            ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.query.isBlank {
            ContentUnavailableView("Search Your History", systemImage: "magnifyingglass",
                                   description: Text("Prompts, replies, memory notes, skills and file snapshots."))
        } else if model.hits.isEmpty {
            ContentUnavailableView.search(text: model.query)
        }
    }

    private var statusBar: some View {
        Text(model.isIndexing ? model.progress : model.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
    }
}

struct HitRow: View {
    let hit: Hit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoleBadge(role: hit.role, isDoc: hit.type == "doc")
                if hit.sidechain {
                    Text("agent").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
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
    }

    /// Bolds the text between FTS5 snippet markers.
    private func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(snippet)
        while let open = rest.range(of: Marks.open) {
            result += AttributedString(rest[..<open.lowerBound])
            rest = rest[open.upperBound...]
            let close = rest.range(of: Marks.close) ?? rest.endIndex..<rest.endIndex
            var match = AttributedString(rest[..<close.lowerBound])
            match.inlinePresentationIntent = .stronglyEmphasized
            match.foregroundColor = .primary
            result += match
            rest = rest[close.upperBound...]
        }
        result += AttributedString(rest)
        return result
    }
}

struct RoleBadge: View {
    let role: String
    var isDoc = false

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        guard !isDoc else { return role }
        switch role {
        case "user": return "you"
        case "assistant": return "claude"
        default: return role
        }
    }

    private var color: Color {
        guard !isDoc else { return .orange }
        switch role {
        case "user": return .blue
        case "assistant": return .purple
        default: return .gray
        }
    }
}
