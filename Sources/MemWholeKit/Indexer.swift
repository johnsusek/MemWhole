import Foundation

public struct IndexStats: Sendable {
    public var scanned = 0
    public var indexed = 0
    public var unchanged = 0
    public var removed = 0
    public var messages = 0
    public var docs = 0
}

/// Walks a source folder, matches files against its rules and writes rows for new or changed files.
public final class Indexer {
    private struct Entry {
        let url: URL
        let relativePath: String
        let rule: Rule
        let size: Int64
        let mtime: Double
    }

    private struct KnownFile {
        let id: Int64
        let size: Int64
        let mtime: Double
        let offset: Int64
    }

    /// Session fields collected while reading one transcript file, merged into `sessions` at the end.
    private struct SessionInfo {
        var project: String?
        var customTitle: String?
        var aiTitle: String?
        var firstPrompt: String?
        var branch: String?
        var firstTS: String?
        var lastTS: String?

        mutating func note(_ ts: String?) {
            guard let ts else { return }
            if firstTS == nil || ts < firstTS! { firstTS = ts }
            if lastTS == nil || ts > lastTS! { lastTS = ts }
        }
    }

    private let db: Database
    private let root: URL
    private let rules: RuleSet
    private var projectDirs: [String: String] = [:]
    private var stats = IndexStats()

    private let insertMessage: Statement
    private let insertDoc: Statement
    private let upsertSession: Statement
    private let insertProjectDir: Statement

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(db: Database, root: URL, rules: RuleSet) throws {
        self.db = db
        self.root = root
        self.rules = rules
        insertMessage = try db.prepare("""
            INSERT INTO messages(file_id, session_id, role, ts, text, tool_name, file_path, is_sidechain)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """)
        insertDoc = try db.prepare("""
            INSERT INTO docs(file_id, source, path, kind, title, body, project, session_id, ts)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        upsertSession = try db.prepare("""
            INSERT INTO sessions(id, project, custom_title, ai_title, first_prompt, branch, first_ts, last_ts)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project = COALESCE(sessions.project, excluded.project),
                custom_title = COALESCE(excluded.custom_title, sessions.custom_title),
                ai_title = COALESCE(excluded.ai_title, sessions.ai_title),
                first_prompt = COALESCE(sessions.first_prompt, excluded.first_prompt),
                branch = COALESCE(excluded.branch, sessions.branch),
                first_ts = MIN(COALESCE(sessions.first_ts, excluded.first_ts), COALESCE(excluded.first_ts, sessions.first_ts)),
                last_ts = MAX(COALESCE(sessions.last_ts, excluded.last_ts), COALESCE(excluded.last_ts, sessions.last_ts))
            """)
        insertProjectDir = try db.prepare("INSERT OR REPLACE INTO project_dirs(dir, project) VALUES (?, ?)")

        let dirs = try db.prepare("SELECT dir, project FROM project_dirs")
        while try dirs.step() {
            if let dir = dirs.text(0), let project = dirs.text(1) { projectDirs[dir] = project }
        }
    }

    /// Opens (or with `full`, recreates) the index at `databasePath` and brings it up to date with `folder`.
    public static func index(folder: URL, databasePath: String, full: Bool,
                             progress: (String) -> Void) throws -> IndexStats {
        if full {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databasePath + suffix) }
        }
        let db = try Schema.open(path: databasePath)
        let stats = try Indexer(db: db, root: folder, rules: .claude).run(progress: progress)
        try db.exec("""
            INSERT INTO messages_fts(messages_fts) VALUES ('optimize');
            INSERT INTO docs_fts(docs_fts) VALUES ('optimize');
            """)
        return stats
    }

    /// The real path of a folder, or nil if it isn't one.
    /// realpath, not resolvingSymlinksInPath: the latter turns /private/tmp into /tmp,
    /// while the directory enumerator reports /private/tmp, so relative paths would not match.
    public static func resolveFolder(_ path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue,
              let resolved = realpath(expanded, nil) else { return nil }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    public func run(progress: (String) -> Void) throws -> IndexStats {
        let entries = try walk()
        let known = try knownFiles()
        let total = entries.count
        stats.scanned = total

        for (number, entry) in entries.enumerated() {
            if let file = known[entry.url.path], file.size == entry.size, file.mtime == entry.mtime {
                stats.unchanged += 1
                continue
            }
            progress("[\(number + 1)/\(total)] \(entry.relativePath)")
            try db.transaction { try index(entry, known: known[entry.url.path]) }
            stats.indexed += 1
        }

        // Files that are gone, or older snapshot versions that a newer one replaced.
        let seen = Set(entries.map(\.url.path))
        let rootPrefix = root.path + "/"
        let stale = known.filter { $0.key.hasPrefix(rootPrefix) && !seen.contains($0.key) }
        if !stale.isEmpty {
            try db.transaction {
                for file in stale.values { try removeRows(fileID: file.id, dropFile: true) }
            }
            stats.removed = stale.count
        }
        return stats
    }

    // MARK: - Walk

    private func walk() throws -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw SQLiteError(description: "Cannot read \(root.path)")
        }
        let rootPrefix = root.path + "/"
        var entries: [Entry] = []
        // file-history/<session>/<hash> -> highest version seen
        var snapshots: [String: (version: Int, entry: Entry)] = [:]

        for case let url as URL in enumerator {
            let path = url.path
            guard path.hasPrefix(rootPrefix) else { continue }
            let relativePath = String(path.dropFirst(rootPrefix.count))
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if rules.prunes(directory: relativePath) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                  let rule = rules.rule(for: relativePath), rule.parser != .skip else { continue }
            let entry = Entry(
                url: url,
                relativePath: relativePath,
                rule: rule,
                size: Int64(values.fileSize ?? 0),
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0)

            if rule.parser == .snapshot {
                let parts = relativePath.split(separator: "@v", maxSplits: 1)
                let key = String(parts[0])
                let version = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                if version >= snapshots[key]?.version ?? -1 { snapshots[key] = (version, entry) }
            } else {
                entries.append(entry)
            }
        }
        entries += snapshots.values.map(\.entry)

        // Transcripts first, so memory notes can look up their project from transcript `cwd`s.
        return entries.sorted { a, b in
            let aFirst = a.rule.parser == .transcript, bFirst = b.rule.parser == .transcript
            return aFirst != bFirst ? aFirst : a.relativePath < b.relativePath
        }
    }

    private func knownFiles() throws -> [String: KnownFile] {
        let stmt = try db.prepare("SELECT id, path, size, mtime, offset FROM files")
        var files: [String: KnownFile] = [:]
        while try stmt.step() {
            guard let path = stmt.text(1) else { continue }
            files[path] = KnownFile(id: stmt.int64(0), size: stmt.int64(2), mtime: stmt.double(3), offset: stmt.int64(4))
        }
        return files
    }

    // MARK: - Per file

    private func index(_ entry: Entry, known: KnownFile?) throws {
        let appendOnly = entry.rule.parser == .transcript || entry.rule.parser == .history
        var startOffset: UInt64 = 0
        let fileID: Int64

        if let known {
            fileID = known.id
            if appendOnly && entry.size >= known.offset {
                startOffset = UInt64(known.offset)
            } else {
                try removeRows(fileID: fileID, dropFile: false)
            }
        } else {
            try db.prepare("INSERT INTO files(path, size, mtime, offset, parser) VALUES (?, 0, 0, 0, ?)")
                .run(entry.url.path, entry.rule.parser.rawValue)
            fileID = db.lastInsertRowID
        }

        let endOffset: UInt64
        switch entry.rule.parser {
        case .transcript: endOffset = try indexTranscript(entry, fileID: fileID, from: startOffset)
        case .history: endOffset = try indexHistory(entry, fileID: fileID, from: startOffset)
        case .markdown: endOffset = try indexMarkdown(entry, fileID: fileID)
        case .json: endOffset = try indexJSON(entry, fileID: fileID)
        case .snapshot: endOffset = try indexSnapshot(entry, fileID: fileID)
        case .skip: endOffset = 0
        }

        try db.prepare("UPDATE files SET size = ?, mtime = ?, offset = ?, parser = ? WHERE id = ?")
            .run(entry.size, entry.mtime, Int64(endOffset), entry.rule.parser.rawValue, fileID)
    }

    private func removeRows(fileID: Int64, dropFile: Bool) throws {
        try db.prepare("DELETE FROM messages WHERE file_id = ?").run(fileID)
        try db.prepare("DELETE FROM docs WHERE file_id = ?").run(fileID)
        if dropFile {
            try db.prepare("DELETE FROM files WHERE id = ?").run(fileID)
        }
    }

    // MARK: - Transcripts

    private func indexTranscript(_ entry: Entry, fileID: Int64, from offset: UInt64) throws -> UInt64 {
        // projects/<flattened-dir>/...
        let projectDir = entry.relativePath.split(separator: "/")[1]
        var sessions: [String: SessionInfo] = [:]

        let end = try LineReader(path: entry.url.path, startOffset: offset).forEachLine { line in
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = record["type"] as? String,
                  let sessionID = record["sessionId"] as? String else { return }

            switch type {
            case "custom-title":
                sessions[sessionID, default: SessionInfo()].customTitle = record["customTitle"] as? String
            case "ai-title":
                sessions[sessionID, default: SessionInfo()].aiTitle = record["aiTitle"] as? String
            case "user", "assistant":
                // Injected text such as skill bodies, not something either side wrote.
                if record["isMeta"] as? Bool == true { return }
                guard let message = record["message"] as? [String: Any] else { return }
                let ts = record["timestamp"] as? String
                let sidechain = entry.rule.sidechain || record["isSidechain"] as? Bool == true

                var info = sessions[sessionID, default: SessionInfo()]
                info.note(ts)
                if let cwd = record["cwd"] as? String, info.project == nil {
                    info.project = cwd
                    if projectDirs[String(projectDir)] != cwd {
                        projectDirs[String(projectDir)] = cwd
                        try insertProjectDir.run(String(projectDir), cwd)
                    }
                }
                if let branch = record["gitBranch"] as? String, !branch.isEmpty { info.branch = branch }

                for block in Self.blocks(of: message, role: type) {
                    let text = Secrets.maskText(block.text)
                    try insertMessage.run(
                        fileID, sessionID, block.role, ts, text, block.toolName, block.filePath, sidechain)
                    stats.messages += 1
                    if block.role == "user", !sidechain, info.firstPrompt == nil {
                        info.firstPrompt = Self.titleLine(text)
                    }
                }
                sessions[sessionID] = info
            default:
                return
            }
        }

        for (id, info) in sessions {
            try upsertSession.run(
                id, info.project, info.customTitle, info.aiTitle, info.firstPrompt, info.branch,
                info.firstTS, info.lastTS)
        }
        return end
    }

    private struct Block {
        let role: String
        let text: String
        var toolName: String? = nil
        var filePath: String? = nil
    }

    /// User and assistant text, plus tool name and file path from tool calls.
    /// Tool results, thinking and images are left out.
    private static func blocks(of message: [String: Any], role: String) -> [Block] {
        if let text = message["content"] as? String {
            return text.isBlank ? [] : [Block(role: role, text: text)]
        }
        guard let content = message["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { block in
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String, !text.isBlank else { return nil }
                return Block(role: role, text: text)
            case "tool_use":
                guard let name = block["name"] as? String else { return nil }
                let input = block["input"] as? [String: Any] ?? [:]
                let path = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String
                let text = [name, path].compactMap { $0 }.joined(separator: " ")
                return Block(role: "tool", text: text, toolName: name, filePath: path)
            default:
                return nil
            }
        }
    }

    // MARK: - Other sources

    private func indexHistory(_ entry: Entry, fileID: Int64, from offset: UInt64) throws -> UInt64 {
        try LineReader(path: entry.url.path, startOffset: offset).forEachLine { line in
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let display = record["display"] as? String, !display.isBlank else { return }
            let ts = (record["timestamp"] as? Double).map { isoFormatter.string(from: Date(timeIntervalSince1970: $0 / 1000)) }
            try addDoc(entry, fileID: fileID, title: nil, body: Secrets.maskText(display),
                       project: record["project"] as? String, sessionID: record["sessionId"] as? String, ts: ts)
        }
    }

    private func indexMarkdown(_ entry: Entry, fileID: Int64) throws -> UInt64 {
        guard let text = readText(entry) else { return 0 }
        let front = Self.frontmatter(text)
        let heading = text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
        let title = front["name"] ?? heading ?? entry.url.deletingPathExtension().lastPathComponent

        var project: String?
        if entry.rule.kind == "memory" {
            project = projectDirs[String(entry.relativePath.split(separator: "/")[1])]
        }
        try addDoc(entry, fileID: fileID, title: title, body: Secrets.maskText(text), project: project)
        return UInt64(entry.size)
    }

    private func indexJSON(_ entry: Entry, fileID: Int64) throws -> UInt64 {
        guard let data = try? Data(contentsOf: entry.url) else { return 0 }
        var title = entry.url.lastPathComponent
        let body: String
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let name = (object as? [String: Any])?["name"] as? String { title = name }
            let masked = Secrets.maskJSON(object)
            let pretty = try JSONSerialization.data(withJSONObject: masked, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            body = String(decoding: pretty, as: UTF8.self)
        } else {
            body = Secrets.maskText(String(decoding: data, as: UTF8.self))
        }
        try addDoc(entry, fileID: fileID, title: title, body: body)
        return UInt64(entry.size)
    }

    private func indexSnapshot(_ entry: Entry, fileID: Int64) throws -> UInt64 {
        guard let text = readText(entry) else { return 0 }
        // file-history/<session>/<hash>@vN. The original path is not recorded, so use the first line as title.
        let sessionID = String(entry.relativePath.split(separator: "/")[1])
        let title = text.split(separator: "\n").first { !$0.isBlank }.map { Self.titleLine(String($0)) }
        try addDoc(entry, fileID: fileID, title: title, body: Secrets.maskText(text), sessionID: sessionID)
        return UInt64(entry.size)
    }

    private func addDoc(_ entry: Entry, fileID: Int64, title: String?, body: String,
                        project: String? = nil, sessionID: String? = nil, ts: String? = nil) throws {
        let ts = ts ?? isoFormatter.string(from: Date(timeIntervalSince1970: entry.mtime))
        try insertDoc.run(fileID, rules.source, entry.relativePath, entry.rule.kind, title, body, project, sessionID, ts)
        stats.docs += 1
    }

    /// UTF-8 text up to 2 MB. Binary files return nil.
    private func readText(_ entry: Entry) -> String? {
        guard entry.size <= 2 << 20, let data = try? Data(contentsOf: entry.url),
              !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    // MARK: - Text helpers

    static func titleLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 100 ? String(trimmed.prefix(100)) + "…" : trimmed
    }

    /// `key: value` pairs from a leading `---` block.
    static func frontmatter(_ text: String) -> [String: String] {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return [:] }
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            if line.hasPrefix("---") { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty, fields[key] == nil { fields[key] = value }
        }
        return fields
    }
}

extension StringProtocol {
    public var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
