import Foundation
import MemWholeKit

let usage = """
    memwhole: local search over ~/.claude-style folders

    USAGE
      memwhole index <folder> [--full]
      memwhole search <words...> [--limit N] [--project TEXT] [--role user|assistant]
                                 [--kind KIND] [--since DATE|7d] [--sort date|relevance] [--raw] [--json]
      memwhole show <session-id-prefix> [--sidechain]
      memwhole stats

    OPTIONS
      --db PATH     Index file (default: $MEMWHOLE_DB or ~/Library/Application Support/MemWhole/index.sqlite)
      --full        Rebuild the index from scratch
      --sort        date (newest first, the default) or relevance
      --raw         Pass the query to SQLite FTS5 as written (AND, OR, NOT, "phrases", prefix*)
      --kind        memory, skill, task, prompt, snapshot, rules, config, plugin-doc, plugin-manifest, changelog

    """

struct Arguments {
    var positionals: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    static let flagNames: Set<String> = ["full", "raw", "json", "sidechain", "help"]

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
    return Store.defaultDatabasePath
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Commands

func runIndex(_ args: Arguments) throws {
    guard let folder = args.positionals.first else { throw CLIError("index needs a folder") }
    guard let root = Indexer.resolveFolder(folder) else {
        throw CLIError("Not a folder: \(folder)")
    }
    let dbPath = databasePath(args)
    let showProgress = isatty(STDERR_FILENO) != 0
    let start = Date()
    let stats = try Indexer.index(folder: root, databasePath: dbPath, full: args.flags.contains("full")) { line in
        guard showProgress else { return }
        let clipped = line.count > 100 ? String(line.prefix(100)) + "…" : line
        FileHandle.standardError.write(Data("\r\u{1B}[2K\(clipped)".utf8))
    }
    if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }

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
    if let sort = args.options["sort"] {
        guard let value = SearchSort(rawValue: sort) else { throw CLIError("--sort must be date or relevance") }
        options.sort = value
    }
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
        default: throw CLIError("--role must be user or assistant")
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
    case ("message", _): label = style.magenta("claude")
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

    let matches = try Store.sessions(db: db, idPrefix: prefix)
    guard let session = matches.first else { throw CLIError("No session starts with \(prefix)") }
    guard matches.count == 1 else {
        throw CLIError("\(prefix) matches several sessions:\n" + matches.map { "  \($0.id)  \($0.title ?? "")" }.joined(separator: "\n"))
    }

    print(style.bold(session.title.map(Format.oneLine) ?? "(untitled)"))
    var details = [session.id, Format.path(session.project)]
    if let branch = session.branch { details.append(branch) }
    details.append("\(Format.date(session.firstTS)) → \(Format.date(session.lastTS))")
    print(style.dim(details.joined(separator: "  ·  ")))
    print()

    let messages = try Store.messages(db: db, sessionID: session.id, includeSidechain: args.flags.contains("sidechain"))
    for message in messages {
        let agent = message.sidechain ? style.dim(" (agent)") : ""
        switch message.role {
        case "user":
            print("\n" + style.cyan("you") + agent + style.dim("  \(Format.date(message.ts))"))
            print(message.text)
        default:
            print("\n" + style.magenta("claude") + agent + style.dim("  \(Format.date(message.ts))"))
            print(message.text)
        }
    }
}

func runStats(_ args: Arguments) throws {
    let dbPath = databasePath(args)
    let db = try Schema.open(path: dbPath)
    let style = Style.stdout

    let counts = try Store.counts(db: db)
    print(style.bold("Sessions") + "  \(counts.sessions)")
    print(style.bold("Files") + "     \(counts.files)")

    print(style.bold("\nMessages"))
    for row in counts.messages {
        let name = row.role + (row.sidechain ? " (agent)" : "")
        print("  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(row.count)")
    }

    print(style.bold("\nDocs"))
    for row in counts.docs {
        let name = row.kind.padding(toLength: 18, withPad: " ", startingAt: 0)
        print("  \(name) \(row.count)  \(style.dim(Format.bytes(row.bytes)))")
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
