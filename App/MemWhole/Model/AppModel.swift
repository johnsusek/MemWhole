import AppKit
import MemWholeKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var query = "" { didSet { scheduleSearch(recount: true) } }
    var sort = SearchSort.date { didSet { scheduleSearch() } }
    var hits: [Hit] = []
    var hasMore = false
    var isLoadingMore = false
    var selection: Hit.ID? { didSet { loadDetail() } }
    var note: Store.Note?
    /// The open note's body with matches between `Marks`, or nil when the body has none.
    var markedBody: String?
    /// Changes whenever a new note loads, so its view (and its place among the matches) starts over.
    var detailKey = ""
    /// Set by Find… (⌘F) to move focus to the search field.
    var isSearchFocused = false

    var isIndexing = false
    var progress = ""
    var status = ""
    /// Notes the current query finds (every note, when it's blank), or nil before the first search.
    var total: Int?
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

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Set when the query or index changes, until a search brings back fresh counts.
    @ObservationIgnored private var countsAreStale = true

    init() {
        refreshStatus()
        scheduleSearch(recount: true)
    }

    // MARK: - Search

    /// Results fetched per page; more load as the list scrolls to the end.
    static let pageSize = 200

    /// Fetches the first page for the current query; a blank query lists every note.
    /// The total depends only on the query and the index, so sort changes skip it.
    private func scheduleSearch(recount: Bool = false) {
        searchTask?.cancel()
        if recount { countsAreStale = true }
        hasMore = false
        isLoadingMore = false
        guard hasIndex else {
            hits = []
            total = nil
            return
        }
        let request = searchOptions(offset: 0)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await fetch(request, counts: countsAreStale)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let (hits, total)):
                self.hits = hits
                if let total {
                    self.total = total
                    countsAreStale = false
                }
                hasMore = hits.count == Self.pageSize
                errorMessage = nil
                // A note keeps its id as the query changes; refresh the open note's highlights.
                if let selection, hits.contains(where: { $0.id == selection }) { loadDetail() }
            case .failure(let error):
                self.hits = []
                total = nil
                errorMessage = "\(error)"
            }
        }
    }

    /// Appends the next page of results for the current search.
    func loadMore() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let request = searchOptions(offset: hits.count)
        let previous = searchTask
        searchTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let result = await fetch(request, counts: false)
            guard !Task.isCancelled else { return }
            isLoadingMore = false
            switch result {
            case .success(let (page, _)):
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
        options.sort = sort
        return options
    }

    /// A page of results and, when asked, the total, read over one connection.
    private func fetch(_ request: SearchOptions, counts: Bool) async -> Result<([Hit], Int?), Error> {
        let path = databasePath
        return await Task.detached {
            Result {
                let db = try Schema.open(path: path)
                let hits = try Search.run(db: db, options: request, marks: (Marks.open, Marks.close))
                return (hits, counts ? try Search.count(db: db, options: request) : nil)
            }
        }.value
    }

    private func loadDetail() {
        guard let id = selection else {
            note = nil
            markedBody = nil
            return
        }
        let path = databasePath
        let match = Search.match(searchOptions(offset: 0))
        let marks = (Marks.open, Marks.close)
        let key = "\(id)|\(match)"
        Task {
            let loaded: (Store.Note, String?)? = await Task.detached {
                guard let db = try? Schema.open(path: path), let note = try? Store.note(db: db, id: id) else { return nil }
                let body = try? Search.markedBody(db: db, match: match, noteID: id, marks: marks)
                return (note, body ?? nil)
            }.value
            // Ignore a slow load that finished after the selection moved on.
            if selection == id {
                note = loaded?.0
                markedBody = loaded?.1
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
                scheduleSearch(recount: true)
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
            var parts = [
                "\(counts.notes.formatted()) notes",
                "\(counts.projects.formatted()) projects",
            ]
            if let lastRun { parts.append(lastRun) }
            status = parts.joined(separator: " · ")
        }
    }

    // MARK: - Trash

    var canTrashSelection: Bool { selection != nil && folderPath != nil && !isIndexing }

    /// Moves the selected note to the Trash, drops its MEMORY.md pointer, and selects a neighbor.
    func trashSelection() {
        guard canTrashSelection, let id = selection, let folderPath,
              let row = hits.firstIndex(where: { $0.id == id }) else { return }
        let hit = hits[row]
        do {
            try Memories.trash(notePath: hit.path, in: URL(fileURLWithPath: folderPath))
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t move “\(Format.oneLine(hit.title ?? hit.path))” to the Trash."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        hits.remove(at: row)
        total = total.map { max($0 - 1, 0) }
        selection = hits.isEmpty ? nil : hits[min(row, hits.count - 1)].id
        reindex()
    }

    // MARK: - Files and pasteboard

    /// The file a note path (relative to the indexed folder) points at.
    func fileURL(forNotePath path: String) -> URL? {
        guard let folderPath else { return nil }
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
