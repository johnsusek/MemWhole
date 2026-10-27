import AppKit
import MemWholeKit
import Observation

/// Which slice of the index a search covers.
enum Scope: String, CaseIterable, Identifiable {
    case all, memory, skills, prompts, snapshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Everything"
        case .memory: "Memory"
        case .skills: "Skills"
        case .prompts: "Prompt history"
        case .snapshots: "File snapshots"
        }
    }

    var kind: String? {
        switch self {
        case .memory: "memory"
        case .skills: "skill"
        case .prompts: "prompt"
        case .snapshots: "snapshot"
        default: nil
        }
    }
}

enum Detail: Sendable {
    case session(Store.Session, [Store.Message], focus: Int64?)
    case doc(Store.Doc)
}

/// Snippet highlight markers; `HitRow` turns them into bold text.
enum Marks {
    static let open = "\u{1}"
    static let close = "\u{2}"
}

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

    var isIndexing = false
    var progress = ""
    var status = ""
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

    init() {
        refreshStatus()
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
            return
        }
        let request = searchOptions(offset: 0)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await fetch(request)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let hits):
                self.hits = hits
                hasMore = hits.count == Self.pageSize
                errorMessage = nil
            case .failure(let error):
                self.hits = []
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
        options.sort = sort
        return options
    }

    private func fetch(_ request: SearchOptions) async -> Result<[Hit], Error> {
        let path = databasePath
        return await Task.detached {
            Result { try Search.run(db: Schema.open(path: path), options: request, marks: (Marks.open, Marks.close)) }
        }.value
    }

    private func loadDetail() {
        guard let id = selection, let hit = hits.first(where: { $0.id == id }) else {
            detail = nil
            return
        }
        let path = databasePath
        Task {
            let loaded: Detail? = await Task.detached {
                let db = try? Schema.open(path: path)
                guard let db else { return nil }
                if hit.type == "doc" {
                    return (try? Store.doc(db: db, id: hit.rowID)).flatMap { $0.map(Detail.doc) }
                }
                guard let sessionID = hit.sessionID,
                      let session = try? Store.sessions(db: db, idPrefix: sessionID).first,
                      let messages = try? Store.messages(db: db, sessionID: sessionID, includeSidechain: hit.sidechain)
                else { return nil }
                return .session(session, messages, focus: hit.rowID)
            }.value
            // Ignore a slow load that finished after the selection moved on.
            if selection == id { detail = loaded }
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

    func revealInFinder(_ doc: Store.Doc) {
        guard let folderPath else { return }
        let url = URL(fileURLWithPath: folderPath).appendingPathComponent(doc.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
