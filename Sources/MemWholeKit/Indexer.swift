import Foundation

public struct IndexStats: Sendable {
    public var scanned = 0
    public var indexed = 0
    public var unchanged = 0
    public var removed = 0
}

/// Walks one source's folder and writes rows for new or changed notes.
public final class Indexer {
    private struct Entry {
        let url: URL
        let relativePath: String
        /// The `projects/<dir>` folder name a Claude note sits under.
        let projectDir: String?
        let size: Int64
        let mtime: Double
    }

    private struct KnownFile {
        let id: Int64
        let size: Int64
        let mtime: Double
    }

    private let db: Database
    private let source: MemorySource
    private let root: URL
    private var projectDirs: [String: String] = [:]
    /// Folders already searched for a `cwd` this run without finding one.
    private var unknownProjectDirs: Set<String> = []
    private var stats = IndexStats()

    private let insertNote: Statement
    private let insertProjectDir: Statement

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(db: Database, source: MemorySource, root: URL) throws {
        self.db = db
        self.source = source
        self.root = root
        insertNote = try db.prepare("""
            INSERT INTO notes(file_id, source, path, title, body, project, ts) VALUES (?, ?, ?, ?, ?, ?, ?)
            """)
        insertProjectDir = try db.prepare("INSERT OR REPLACE INTO project_dirs(dir, project) VALUES (?, ?)")

        let dirs = try db.prepare("SELECT dir, project FROM project_dirs")
        while try dirs.step() {
            if let dir = dirs.text(0), let project = dirs.text(1) { projectDirs[dir] = project }
        }
    }

    /// Opens (or with `full`, recreates) the index at `databasePath` and brings it up to date with every source.
    public static func index(roots: [MemorySource: URL] = MemorySource.roots, databasePath: String, full: Bool,
                             progress: (String) -> Void) throws -> IndexStats {
        if full {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databasePath + suffix) }
        }
        let db = try Schema.open(path: databasePath)
        var stats = IndexStats()

        for (source, root) in roots {
            let run = try Indexer(db: db, source: source, root: root).run(progress: progress)
            stats.scanned += run.scanned
            stats.indexed += run.indexed
            stats.unchanged += run.unchanged
            stats.removed += run.removed
        }

        try db.exec("INSERT INTO notes_fts(notes_fts) VALUES ('optimize')")
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
            progress("[\(number + 1)/\(total)] \(source.title): \(entry.relativePath)")
            try db.transaction { try index(entry, known: known[entry.url.path]) }
            stats.indexed += 1
        }

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
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let rootPrefix = root.path + "/"
        var entries: [Entry] = []

        for (url, projectDir) in source == .claude ? claudeFiles() : codexFiles() {
            guard url.path.hasPrefix(rootPrefix), let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            entries.append(Entry(
                url: url,
                relativePath: String(url.path.dropFirst(rootPrefix.count)),
                projectDir: projectDir,
                size: Int64(values.fileSize ?? 0),
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }

        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    /// Every `projects/*/memory/**/*.md` except the `MEMORY.md` index of pointers.
    private func claudeFiles() -> [(url: URL, projectDir: String?)] {
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects.path) else { return [] }

        var files: [(url: URL, projectDir: String?)] = []

        for dir in dirs.sorted() {
            let memory = projects.appendingPathComponent(dir).appendingPathComponent("memory", isDirectory: true)
            guard let enumerator = fm.enumerator(at: memory, includingPropertiesForKeys: nil) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "md" && url.lastPathComponent != "MEMORY.md" {
                files.append((url, dir))
            }
        }

        return files
    }

    /// The consolidated memory and the notes written by hand. `raw_memories.md` and `rollout_summaries/` feed the
    /// consolidation, so they would only repeat it.
    private func codexFiles() -> [(url: URL, projectDir: String?)] {
        let notes = root.appendingPathComponent("extensions/ad_hoc/notes", isDirectory: true)
        let adHoc = (try? FileManager.default.contentsOfDirectory(at: notes, includingPropertiesForKeys: nil)) ?? []
        let consolidated = [root.appendingPathComponent("MEMORY.md"), root.appendingPathComponent("memory_summary.md")]
        return (consolidated + adHoc.filter { $0.pathExtension == "md" }).map { ($0, nil) }
    }

    private func knownFiles() throws -> [String: KnownFile] {
        let stmt = try db.prepare("SELECT id, path, size, mtime FROM files")
        var files: [String: KnownFile] = [:]
        while try stmt.step() {
            guard let path = stmt.text(1) else { continue }
            files[path] = KnownFile(id: stmt.int64(0), size: stmt.int64(2), mtime: stmt.double(3))
        }
        return files
    }

    // MARK: - Per file

    private func index(_ entry: Entry, known: KnownFile?) throws {
        let fileID: Int64
        if let known {
            fileID = known.id
            try removeRows(fileID: fileID, dropFile: false)
        } else {
            try db.prepare("INSERT INTO files(path, size, mtime) VALUES (?, 0, 0)").run(entry.url.path)
            fileID = db.lastInsertRowID
        }

        if let text = readText(entry) {
            let modified = isoFormatter.string(from: Date(timeIntervalSince1970: entry.mtime))

            for note in try notes(in: text, entry) {
                try insertNote.run(fileID, source.rawValue, entry.url.path, note.title, Secrets.maskText(note.body),
                                   note.project, note.ts ?? modified)
            }
        }

        try db.prepare("UPDATE files SET size = ?, mtime = ? WHERE id = ?").run(entry.size, entry.mtime, fileID)
    }

    private func notes(in text: String, _ entry: Entry) throws -> [Note] {
        if source == .codex, entry.url.lastPathComponent == "MEMORY.md" { return CodexMemories.taskGroups(in: text) }
        if source == .codex, entry.url.lastPathComponent == "memory_summary.md" {
            return [Note(title: "Memory Summary", body: text)]
        }

        let front = Self.frontmatter(text)
        let heading = text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
        let title = front["name"] ?? heading ?? entry.url.deletingPathExtension().lastPathComponent
        return [Note(title: title, body: text, project: try entry.projectDir.flatMap { try project(forDir: $0) })]
    }

    private func removeRows(fileID: Int64, dropFile: Bool) throws {
        try db.prepare("DELETE FROM notes WHERE file_id = ?").run(fileID)
        if dropFile {
            try db.prepare("DELETE FROM files WHERE id = ?").run(fileID)
        }
    }

    // MARK: - Projects

    /// The working directory a `projects/<dir>` folder stands for. Folder names flatten paths lossily
    /// (`/` and `.` both become `-`), so read the first `cwd` from one of the folder's transcripts.
    private func project(forDir dir: String) throws -> String? {
        if let project = projectDirs[dir] { return project }
        guard !unknownProjectDirs.contains(dir) else { return nil }

        let folder = root.appendingPathComponent("projects").appendingPathComponent(dir)
        let transcripts = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
        for name in transcripts {
            if let cwd = Self.firstCWD(in: folder.appendingPathComponent(name)) {
                projectDirs[dir] = cwd
                try insertProjectDir.run(dir, cwd)
                return cwd
            }
        }
        if let path = Self.existingPath(flattened: dir) {
            projectDirs[dir] = path
            try insertProjectDir.run(dir, path)
            return path
        }
        unknownProjectDirs.insert(dir)
        return nil
    }

    /// A directory on disk whose flattened form (`/` and `.` as `-`) is `flattened`, for folders with no
    /// transcript to read a `cwd` from. Walks down from `/`, only into children that keep the name matching.
    static func existingPath(flattened: String, under parent: String = "/") -> String? {
        let fm = FileManager.default
        guard flattened.hasPrefix("-"),
              let children = try? fm.contentsOfDirectory(atPath: parent) else { return nil }
        let rest = flattened.dropFirst()
        for child in children.sorted(by: { $0.count > $1.count }) {
            let flat = child.replacingOccurrences(of: ".", with: "-")
            guard rest.hasPrefix(flat) else { continue }
            let path = (parent as NSString).appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let remainder = String(rest.dropFirst(flat.count))
            if remainder.isEmpty { return path }
            if let found = existingPath(flattened: remainder, under: path) { return found }
        }
        return nil
    }

    /// The first `cwd` field among a transcript's opening records.
    private static func firstCWD(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 << 10) else { return nil }
        for line in data.split(separator: 0x0A) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let cwd = record["cwd"] as? String, !cwd.isEmpty { return cwd }
        }
        return nil
    }

    // MARK: - Text helpers

    /// UTF-8 text up to 2 MB. Binary files return nil.
    private func readText(_ entry: Entry) -> String? {
        guard entry.size <= 2 << 20, let data = try? Data(contentsOf: entry.url),
              !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
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
