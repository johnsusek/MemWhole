import Foundation

let usage = """
    memwhole: local search over ~/.claude-style folders

    USAGE
      memwhole index <folder> [--full]
      memwhole search <words...> [--limit N] [--project TEXT] [--role user|assistant|tool]
                                 [--kind KIND] [--since DATE|7d] [--raw] [--json]
      memwhole show <session-id-prefix> [--sidechain] [--no-tools]
      memwhole stats

    OPTIONS
      --db PATH     Index file (default: $MEMWHOLE_DB or ~/Library/Application Support/MemWhole/index.sqlite)
      --full        Rebuild the index from scratch
      --raw         Pass the query to SQLite FTS5 as written (AND, OR, NOT, "phrases", prefix*)
      --kind        memory, skill, task, prompt, snapshot, rules, config, plugin-doc, plugin-manifest, changelog

    """

struct Arguments {
    var positionals: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    static let flagNames: Set<String> = ["full", "raw", "json", "sidechain", "no-tools", "help"]

    init(_ args: some Sequence<String>) throws {
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if arg == "-h" {
                flags.insert("help")
            } else if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if let eq = name.firstIndex(of: "=") {
                    options[String(name[..<eq])] = String(name[name.index(after: eq)...])
                } else if Self.flagNames.contains(name) {
                    flags.insert(name)
                } else if let value = iterator.next() {
                    options[name] = value
                } else {
                    throw CLIError("--\(name) needs a value")
                }
            } else {
                positionals.append(arg)
            }
        }
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func databasePath(_ args: Arguments) -> String {
    if let path = args.options["db"] { return (path as NSString).expandingTildeInPath }
    if let path = ProcessInfo.processInfo.environment["MEMWHOLE_DB"] { return (path as NSString).expandingTildeInPath }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("MemWhole/index.sqlite").path
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Commands

func runIndex(_ args: Arguments) throws {
    guard let folder = args.positionals.first else { throw CLIError("index needs a folder") }
    // realpath, not resolvingSymlinksInPath: the latter turns /private/tmp into /tmp,
    // while the directory enumerator reports /private/tmp, so relative paths would not match.
    let expanded = (folder as NSString).expandingTildeInPath
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue,
          let resolved = realpath(expanded, nil) else {
        throw CLIError("Not a folder: \(expanded)")
    }
    let root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    free(resolved)

    let dbPath = databasePath(args)
    if args.flags.contains("full") {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbPath + suffix) }
    }
    let db = try Schema.open(path: dbPath)

    let showProgress = isatty(STDERR_FILENO) != 0
    let start = Date()
    let stats = try Indexer(db: db, root: root, rules: .claude).run { line in
        guard showProgress else { return }
        let clipped = line.count > 100 ? String(line.prefix(100)) + "…" : line
        FileHandle.standardError.write(Data("\r\u{1B}[2K\(clipped)".utf8))
    }
    if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
    try db.exec("INSERT INTO messages_fts(messages_fts) VALUES ('optimize'); INSERT INTO docs_fts(docs_fts) VALUES ('optimize');")

    let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
    print("""
        Indexed \(stats.indexed) of \(stats.scanned) files in \(seconds)s \
        (\(stats.unchanged) unchanged, \(stats.removed) removed)
        Added \(stats.messages) messages and \(stats.docs) docs
        Index: \(Format.path(dbPath))
        """)
}

func runSearch(_ args: Arguments) throws {
    var options = SearchOptions()
    options.query = args.positionals.joined(separator: " ")
    guard !options.query.isBlank else { throw CLIError("search needs some words") }
    options.raw = args.flags.contains("raw")
    options.project = args.options["project"]
    options.kind = args.options["kind"]
    if let limit = args.options["limit"] {
        guard let n = Int(limit), n > 0 else { throw CLIError("--limit must be a positive number") }
        options.limit = n
    }
    if let role = args.options["role"] {
        switch role {
        case "user", "you": options.role = "user"
        case "assistant", "claude": options.role = "assistant"
        case "tool": options.role = "tool"
        default: throw CLIError("--role must be user, assistant or tool")
        }
    }
    if let since = args.options["since"] { options.since = try parseSince(since) }

    let db = try Schema.open(path: databasePath(args))
    let json = args.flags.contains("json")
    let style = json ? Style(enabled: false) : Style.stdout
    let hits: [Hit]
    do {
        hits = try Search.run(db: db, options: options, marks: json ? ("", "") : style.marks)
    } catch let error as SQLiteError where options.raw {
        throw CLIError("Query error: \(error.description.split(separator: "\n")[0])")
    }

    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(hits), as: UTF8.self))
        return
    }
    if hits.isEmpty {
        print("No matches.")
        return
    }
    for hit in hits {
        print(render(hit, style: style))
    }
}

func render(_ hit: Hit, style: Style) -> String {
    let label: String
    switch (hit.type, hit.role) {
    case ("message", "user"): label = style.cyan("you")
    case ("message", "assistant"): label = style.magenta("claude")
    case ("message", _): label = style.dim("tool")
    default: label = style.yellow(hit.role)
    }

    var header = ["[\(label)\(hit.sidechain ? style.dim(" · agent") : "")]", Format.date(hit.ts)]
    if let project = hit.project { header.append(Format.path(project)) }
    if let title = hit.title, !title.isBlank { header.append(style.bold(Format.oneLine(title))) }

    var where_: String
    if hit.type == "message" {
        where_ = "memwhole show \(Format.shortID(hit.sessionID))"
    } else {
        where_ = hit.path ?? ""
    }
    let snippet = Format.oneLine(hit.snippet)
    return header.joined(separator: "  ") + "\n    " + snippet + "\n    " + style.dim(where_) + "\n"
}

/// `2026-10-01`, a full ISO timestamp, or a relative `7d` / `12h`.
func parseSince(_ value: String) throws -> String {
    if let unit = value.last, let amount = Double(value.dropLast()), unit == "d" || unit == "h" {
        let seconds = amount * (unit == "d" ? 86_400 : 3_600)
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date().addingTimeInterval(-seconds))
    }
    guard value.range(of: #"^\d{4}-\d{2}(-\d{2})?"#, options: .regularExpression) != nil else {
        throw CLIError("--since takes a date like 2026-10-01, or 7d / 12h")
    }
    return value
}

func runShow(_ args: Arguments) throws {
    guard let prefix = args.positionals.first, !prefix.isBlank else { throw CLIError("show needs a session id") }
    let db = try Schema.open(path: databasePath(args))
    let style = Style.stdout

    let sessions = try db.prepare("""
        SELECT id, project, COALESCE(custom_title, ai_title, first_prompt), branch, first_ts, last_ts
        FROM sessions WHERE id LIKE ? || '%' ORDER BY last_ts DESC LIMIT 5
        """)
    try sessions.bind([prefix])
    var matches: [(id: String, project: String?, title: String?, branch: String?, first: String?, last: String?)] = []
    while try sessions.step() {
        matches.append((sessions.text(0) ?? "", sessions.text(1), sessions.text(2), sessions.text(3),
                        sessions.text(4), sessions.text(5)))
    }
    guard let session = matches.first else { throw CLIError("No session starts with \(prefix)") }
    guard matches.count == 1 else {
        throw CLIError("\(prefix) matches several sessions:\n" + matches.map { "  \($0.id)  \($0.title ?? "")" }.joined(separator: "\n"))
    }

    print(style.bold(session.title.map(Format.oneLine) ?? "(untitled)"))
    var details = [session.id, Format.path(session.project)]
    if let branch = session.branch { details.append(branch) }
    details.append("\(Format.date(session.first)) → \(Format.date(session.last))")
    print(style.dim(details.joined(separator: "  ·  ")))
    print()

    let includeSidechain = args.flags.contains("sidechain")
    let includeTools = !args.flags.contains("no-tools")
    let messages = try db.prepare("""
        SELECT role, ts, text, is_sidechain FROM messages
        WHERE session_id = ? AND (? OR is_sidechain = 0)
        ORDER BY ts, id
        """)
    try messages.bind([session.id, includeSidechain])
    while try messages.step() {
        let role = messages.text(0) ?? ""
        let text = messages.text(2) ?? ""
        let agent = messages.int(3) != 0 ? style.dim(" (agent)") : ""
        switch role {
        case "tool":
            if includeTools { print(style.dim("  → \(Format.path(text))") + agent) }
        case "user":
            print("\n" + style.cyan("you") + agent + style.dim("  \(Format.date(messages.text(1)))"))
            print(text)
        default:
            print("\n" + style.magenta("claude") + agent + style.dim("  \(Format.date(messages.text(1)))"))
            print(text)
        }
    }
}

func runStats(_ args: Arguments) throws {
    let dbPath = databasePath(args)
    let db = try Schema.open(path: dbPath)
    let style = Style.stdout

    let count = { (sql: String) in try db.prepare(sql).scalar() ?? 0 }
    print(style.bold("Sessions") + "  \(try count("SELECT COUNT(*) FROM sessions"))")
    print(style.bold("Files") + "     \(try count("SELECT COUNT(*) FROM files"))")

    print(style.bold("\nMessages"))
    let roles = try db.prepare("SELECT role, is_sidechain, COUNT(*) FROM messages GROUP BY 1, 2 ORDER BY 3 DESC")
    while try roles.step() {
        let name = (roles.text(0) ?? "") + (roles.int(1) != 0 ? " (agent)" : "")
        print("  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(roles.int(2))")
    }

    print(style.bold("\nDocs"))
    let kinds = try db.prepare("SELECT kind, COUNT(*), SUM(LENGTH(body)) FROM docs GROUP BY 1 ORDER BY 2 DESC")
    while try kinds.step() {
        let name = (kinds.text(0) ?? "").padding(toLength: 18, withPad: " ", startingAt: 0)
        print("  \(name) \(kinds.int(1))  \(style.dim(Format.bytes(kinds.int64(2))))")
    }

    let size = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
    print("\n" + style.dim("Index: \(Format.path(dbPath))  \(Format.bytes(size))"))
}

// MARK: - Entry point

do {
    var rawArgs = Array(CommandLine.arguments.dropFirst())
    let command = rawArgs.isEmpty ? "help" : rawArgs.removeFirst()
    let args = try Arguments(rawArgs)
    if args.flags.contains("help") {
        print(usage)
        exit(0)
    }
    switch command {
    case "index": try runIndex(args)
    case "search", "s": try runSearch(args)
    case "show": try runShow(args)
    case "stats": try runStats(args)
    case "help", "-h", "--help": print(usage)
    default: throw CLIError("Unknown command: \(command)\n\n\(usage)")
    }
} catch {
    printError("memwhole: \(error)")
    exit(1)
}
