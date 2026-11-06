import Foundation

public struct SearchOptions: Sendable {
    public var query = ""
    public var limit = 20
    /// Rows to skip, for paging through results.
    public var offset = 0
    public var project: String?
    /// ISO date or timestamp prefix, compared against `ts`.
    public var since: String?
    /// Pass the query to FTS5 as written instead of quoting each word.
    public var raw = false
    public var sort = SearchSort.date

    public init() {}
}

public enum SearchSort: String, CaseIterable, Sendable {
    /// Newest first, ties broken by relevance.
    case date
    case relevance
}

public struct Hit: Encodable, Sendable, Identifiable {
    /// The note's row id.
    public let id: Int64
    public let ts: String?
    public let project: String?
    public let title: String?
    public let path: String
    public let snippet: String
    public let score: Double
    /// The whole note, with matches between the search's marks. Left out of JSON: search output stays short.
    public let body: String

    enum CodingKeys: CodingKey {
        case id, ts, project, title, path, snippet, score
    }
}

public enum Search {
    /// Characters of text shown for a result when listing without a query.
    static let previewLength = 400

    /// Quotes each word so punctuation can't break FTS5 syntax. The last word matches as a prefix.
    public static func ftsQuery(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        return words.enumerated().map { index, word in
            "\"\(word)\"" + (index == words.count - 1 ? "*" : "")
        }.joined(separator: " ")
    }

    /// The FTS5 expression for the options' query.
    public static func match(_ options: SearchOptions) -> String {
        options.raw ? options.query : ftsQuery(options.query)
    }

    /// Searches for the options' query, or lists every note the other options allow when the query is blank.
    public static func run(db: Database, options: SearchOptions, marks: (open: String, close: String)) throws -> [Hit] {
        let match = match(options)
        let browsing = match.isEmpty
        let (filter, filterParams) = filter(options, match: match)
        let snippet = browsing ? "substr(n.body, 1, \(previewLength))" : "snippet(notes_fts, -1, ?, ?, '…', 24)"
        let score = browsing ? "0.0" : "bm25(notes_fts, 4.0, 1.0)"
        let body = browsing ? "n.body" : "highlight(notes_fts, 1, ?, ?)"

        let stmt = try db.prepare("""
            SELECT n.id, n.ts, n.project, n.title, n.path, \(snippet), \(score), \(body)
            FROM \(source(browsing))
            WHERE \(filter)
            \(options.sort == .date ? "ORDER BY 2 DESC, 7, 1" : "ORDER BY 7, 1")
            LIMIT ? OFFSET ?
            """)
        try stmt.bind((browsing ? [] : [marks.open, marks.close, marks.open, marks.close]) + filterParams + [options.limit, options.offset])
        var hits: [Hit] = []
        while try stmt.step() {
            hits.append(Hit(
                id: stmt.int64(0),
                ts: stmt.text(1),
                project: stmt.text(2),
                title: stmt.text(3),
                path: stmt.text(4) ?? "",
                snippet: stmt.text(5) ?? "",
                score: stmt.double(6),
                body: stmt.text(7) ?? ""))
        }
        return hits
    }

    /// How many notes the options' query finds (all of them, when it's blank), before paging.
    public static func count(db: Database, options: SearchOptions) throws -> Int {
        let match = match(options)
        let (filter, params) = filter(options, match: match)
        let stmt = try db.prepare("SELECT COUNT(*) FROM \(source(match.isEmpty)) WHERE \(filter)")
        try stmt.bind(params)
        return try stmt.step() ? stmt.int(0) : 0
    }

    private static func source(_ browsing: Bool) -> String {
        browsing ? "notes n" : "notes_fts JOIN notes n ON n.id = notes_fts.rowid"
    }

    /// WHERE clause and parameters for notes (`n`), matching `match` unless it's empty.
    private static func filter(_ options: SearchOptions, match: String) -> (String, [SQLBindable?]) {
        var conditions: [String] = []
        var params: [SQLBindable?] = []
        if !match.isEmpty { conditions.append("notes_fts MATCH ?"); params.append(match) }
        if let project = options.project { conditions.append("n.project LIKE ?"); params.append("%\(project)%") }
        if let since = options.since { conditions.append("n.ts >= ?"); params.append(since) }
        return (conditions.isEmpty ? "1" : conditions.joined(separator: " AND "), params)
    }
}
