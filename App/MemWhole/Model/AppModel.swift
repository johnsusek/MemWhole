import AppKit
import MemWholeKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var query = "" { didSet { scheduleSearch() } }
    var scope = Scope.all { didSet { scheduleSearch() } }
    var sort = SearchSort.date { didSet { scheduleSearch() } }
    var hits: [Hit] = []
    var hasMore = false
    var isLoadingMore = false
    var selection: Hit.ID? { didSet { loadDetail() } }
    var detail: Detail?
    /// Changes whenever a new detail loads, so its view (and its place among the matches) starts over.
    var detailKey = ""
    /// Set by Find… (⌘F) to move focus to the search field.
    var isSearchFocused = false

    var isIndexing = false
    var progress = ""
    var status = ""
    var counts: Store.Counts?
    /// Result counts for the current query, or nil when there's no search.
    var searchCounts: Search.Counts?
    var errorMessage: String?

    let databasePath = Store.defaultDatabasePath

    var folderPath: String? {
        get {
            access(keyPath: \.folderPath)
            return UserDefaults.standard.string(forKey: "folderPath")
        }
        set {
            withMutation(keyPath: \.folderPath) {
                UserDefaults.standard.set(newValue, forKey: "folderPath")
            }
        }
    }

    var hasIndex: Bool { FileManager.default.fileExists(atPath: databasePath) }

    /// The sidebar's selection. A source list allows none, but a scope always applies.
    var scopeSelection: Scope? {
        get { scope }
        set { if let newValue { scope = newValue } }
    }

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init() {
        refreshStatus()
    }

    /// The sidebar badge for a scope: its results for the current search, otherwise what it holds.
    func count(for scope: Scope) -> Int {
        if let searchCounts { return scope.count(in: searchCounts) }
        return counts.map { scope.count(in: $0) } ?? 0
    }

    /// A checkmark binding for the View menu's scope items.
    func isShowing(_ scope: Scope) -> Binding<Bool> {
        Binding { self.scope == scope } set: { if $0 { self.scope = scope } }
    }

    // MARK: - Search

    /// Results fetched per page; more load as the list scrolls to the end.
    static let pageSize = 200

    private func scheduleSearch() {
        searchTask?.cancel()
        hasMore = false
        isLoadingMore = false
        guard !query.isBlank else {
            hits = []
            searchCounts = nil
            return
        }
        let request = searchOptions(offset: 0)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            async let counts = fetchCounts(request)
            let result = await fetch(request)
            let searchCounts = await counts
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let hits):
                self.hits = hits
                self.searchCounts = searchCounts
                hasMore = hits.count == Self.pageSize
                errorMessage = nil
                // Grouped hits keep their id as the query changes; refresh the open file's highlights.
                if let selection, hits.contains(where: { $0.id == selection }) { loadDetail() }
            case .failure(let error):
                self.hits = []
                self.searchCounts = nil
                errorMessage = "\(error)"
            }
        }
    }

    /// Appends the next page of results for the current search.
    func loadMore() {
        guard hasMore, !isLoadingMore, !query.isBlank else { return }
        isLoadingMore = true
        let request = searchOptions(offset: hits.count)
        let previous = searchTask
        searchTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let result = await fetch(request)
            guard !Task.isCancelled else { return }
            isLoadingMore = false
            switch result {
            case .success(let page):
                hits += page
                hasMore = page.count == Self.pageSize
            case .failure(let error):
                hasMore = false
                errorMessage = "\(error)"
            }
        }
    }

    private func searchOptions(offset: Int) -> SearchOptions {
        var options = SearchOptions()
        options.query = query
        options.limit = Self.pageSize
        options.offset = offset
        options.kind = scope.kind
        options.messagesOnly = scope == .transcripts
        // The Claude app already shows main conversations; only subagent transcripts are hidden.
        options.sidechainOnly = true
        options.groupByFile = true
        options.sort = sort
        return options
    }

    private func fetch(_ request: SearchOptions) async -> Result<[Hit], Error> {
        let path = databasePath
        return await Task.detached {
            Result { try Search.run(db: Schema.open(path: path), options: request, marks: (Marks.open, Marks.close)) }
        }.value
    }

    private func fetchCounts(_ request: SearchOptions) async -> Search.Counts? {
        let path = databasePath
        return await Task.detached {
            try? Search.counts(db: Schema.open(path: path), options: request)
        }.value
    }

    private func loadDetail() {
        guard let id = selection, let hit = hits.first(where: { $0.id == id }) else {
            detail = nil
            return
        }
        let path = databasePath
        let match = Search.match(searchOptions(offset: 0))
        let marks = (Marks.open, Marks.close)
        let key = "\(id)|\(match)"
        Task {
            let loaded: Detail? = await Task.detached {
                let db = try? Schema.open(path: path)
                guard let db else { return nil }
                if hit.type == "doc" {
                    guard let doc = try? Store.doc(db: db, id: hit.rowID) else { return nil }
                    let body = try? Search.markedBody(db: db, match: match, docID: doc.id, marks: marks)
                    return .doc(doc, markedBody: body ?? nil)
                }
                guard let sessionID = hit.sessionID, let fileID = hit.fileID,
                      let session = try? Store.sessions(db: db, idPrefix: sessionID).first,
                      let messages = try? Store.messages(db: db, fileID: fileID)
                else { return nil }
                let marked = (try? Search.markedMessages(db: db, match: match, fileID: fileID, marks: marks)) ?? [:]
                return .session(session, messages, focus: hit.rowID, marked: marked)
            }.value
            // Ignore a slow load that finished after the selection moved on.
            if selection == id {
                detail = loaded
                detailKey = key
            }
        }
    }

    // MARK: - Indexing

    func chooseFolderAndIndex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = "Index"
        panel.message = "Choose a folder to index, such as ~/.claude"
        panel.directoryURL = folderPath.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        reindex()
    }

    func reindex() {
        guard let folderPath, !isIndexing else { return }
        guard let root = Indexer.resolveFolder(folderPath) else {
            errorMessage = "Not a folder: \(folderPath)"
            return
        }
        isIndexing = true
        progress = "Scanning…"
        errorMessage = nil
        let path = databasePath

        Task {
            let result = await Task.detached {
                Result {
                    try Indexer.index(folder: root, databasePath: path, full: false) { line in
                        Task { @MainActor in self.progress = line }
                    }
                }
            }.value
            isIndexing = false
            progress = ""
            switch result {
            case .success(let stats):
                refreshStatus(lastRun: "Indexed \(stats.indexed) changed files")
                scheduleSearch()
            case .failure(let error):
                errorMessage = "\(error)"
            }
        }
    }

    func refreshStatus(lastRun: String? = nil) {
        guard hasIndex else {
            status = "No index yet"
            return
        }
        let path = databasePath
        Task {
            let counts = await Task.detached { try? Store.counts(db: Schema.open(path: path)) }.value
            guard let counts else { return }
            // Empty after a schema change (or a first run that was cut short): rebuild from the chosen folder.
            if counts.files == 0, folderPath != nil, !isIndexing {
                reindex()
                return
            }
            self.counts = counts
            let messages = counts.messages.reduce(0) { $0 + $1.count }
            let docs = counts.docs.reduce(0) { $0 + $1.count }
            var parts = [
                "\(counts.sessions.formatted()) sessions",
                "\(messages.formatted()) messages",
                "\(docs.formatted()) docs",
            ]
            if let lastRun { parts.append(lastRun) }
            status = parts.joined(separator: " · ")
        }
    }

    // MARK: - Files and pasteboard

    /// The file a doc path (relative to the indexed folder) points at, when there is one on disk.
    func fileURL(forDocPath path: String?, kind: String?) -> URL? {
        guard let folderPath, let path, kind != "prompt" else { return nil }
        return URL(fileURLWithPath: folderPath).appendingPathComponent(path)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
