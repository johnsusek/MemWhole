import AppKit
import MemWholeKit
import Observation

/// Which slice of the index a search covers.
enum Scope: String, CaseIterable, Identifiable {
    case all, you, claude, tools, memory, skills, prompts, snapshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Everything"
        case .you: "Your messages"
        case .claude: "Claude's messages"
        case .tools: "Tool calls"
        case .memory: "Memory"
        case .skills: "Skills"
        case .prompts: "Prompt history"
        case .snapshots: "File snapshots"
        }
    }

    var role: String? {
        switch self {
        case .you: "user"
        case .claude: "assistant"
        case .tools: "tool"
        default: nil
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
    var hits: [Hit] = []
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

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query
        guard !text.isBlank else {
            hits = []
            return
        }
        var options = SearchOptions()
        options.query = text
        options.limit = 200
        options.role = scope.role
        options.kind = scope.kind
        let request = options
        let path = databasePath

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await Task.detached {
                Result { try Search.run(db: Schema.open(path: path), options: request, marks: (Marks.open, Marks.close)) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let hits):
                self.hits = hits
                errorMessage = nil
            case .failure(let error):
                self.hits = []
                errorMessage = "\(error)"
            }
        }
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
