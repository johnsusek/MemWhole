import Foundation

public struct SearchOptions: Sendable {
    public var query = ""
    public var limit = 20
    public var project: String?
    /// user | assistant. Limits results to transcript messages.
    public var role: String?
    /// Doc kind (memory, skill, prompt...). Limits results to docs.
    public var kind: String?
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
    public let type: String          // message | doc
    public let rowID: Int64
    public let sessionID: String?
    public let role: String          // user | assistant, or the doc kind
    public let ts: String?
    public let project: String?
    public let title: String?
    public let path: String?
    public let sidechain: Bool
    public let snippet: String
    public let score: Double

    /// Unique across both tables.
    public var id: String { "\(type)-\(rowID)" }
}

public enum Search {
    /// Rank multiplier for results that are usually noise or duplicates. bm25 scores are negative,
    /// so a smaller multiplier pushes a row down.
    static let sidechainWeight = 0.5
    static let lowKindWeight = 0.5
    static let lowKinds = ["prompt", "snapshot", "plugin-doc", "plugin-manifest", "changelog"]

    /// Quotes each word so punctuation can't break FTS5 syntax. The last word matches as a prefix.
    public static func ftsQuery(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        return words.enumerated().map { index, word in
            "\"\(word)\"" + (index == words.count - 1 ? "*" : "")
        }.joined(separator: " ")
    }

    public static func run(db: Database, options: SearchOptions, marks: (open: String, close: String)) throws -> [Hit] {
        let match = options.raw ? options.query : ftsQuery(options.query)
        guard !match.isEmpty else { return [] }

        var selects: [String] = []
        var params: [SQLBindable?] = []

        if options.kind == nil {
            var sql = """
                SELECT 'message', m.id, m.session_id, m.role, m.ts, s.project,
                       COALESCE(s.custom_title, s.ai_title, s.first_prompt), NULL, m.is_sidechain,
                       snippet(messages_fts, 0, ?, ?, '…', 24),
                       bm25(messages_fts) * CASE WHEN m.is_sidechain THEN \(sidechainWeight) ELSE 1.0 END
                FROM messages_fts
                JOIN messages m ON m.id = messages_fts.rowid
                LEFT JOIN sessions s ON s.id = m.session_id
                WHERE messages_fts MATCH ? AND \(Store.firstCopy)
                """
            params += [marks.open, marks.close, match]
            if let role = options.role { sql += " AND m.role = ?"; params.append(role) }
            if let project = options.project { sql += " AND s.project LIKE ?"; params.append("%\(project)%") }
            if let since = options.since { sql += " AND m.ts >= ?"; params.append(since) }
            selects.append(sql)
        }

        if options.role == nil {
            let lowKinds = lowKinds.map { "'\($0)'" }.joined(separator: ", ")
            var sql = """
                SELECT 'doc', d.id, d.session_id, d.kind, d.ts, COALESCE(d.project, s.project),
                       d.title, d.path, 0,
                       snippet(docs_fts, -1, ?, ?, '…', 24),
                       bm25(docs_fts, 4.0, 1.0) * CASE WHEN d.kind IN (\(lowKinds)) THEN \(lowKindWeight) ELSE 1.0 END
                FROM docs_fts
                JOIN docs d ON d.id = docs_fts.rowid
                LEFT JOIN sessions s ON s.id = d.session_id
                WHERE docs_fts MATCH ?
                """
            params += [marks.open, marks.close, match]
            if let kind = options.kind { sql += " AND d.kind = ?"; params.append(kind) }
            if let project = options.project {
                sql += " AND COALESCE(d.project, s.project) LIKE ?"
                params.append("%\(project)%")
            }
            if let since = options.since { sql += " AND d.ts >= ?"; params.append(since) }
            selects.append(sql)
        }

        let sql = selects.joined(separator: "\nUNION ALL\n")
            + (options.sort == .date ? "\nORDER BY 5 DESC, 11 LIMIT ?" : "\nORDER BY 11 LIMIT ?")
        params.append(options.limit)

        let stmt = try db.prepare(sql)
        try stmt.bind(params)
        var hits: [Hit] = []
        while try stmt.step() {
            hits.append(Hit(
                type: stmt.text(0) ?? "",
                rowID: stmt.int64(1),
                sessionID: stmt.text(2),
                role: stmt.text(3) ?? "",
                ts: stmt.text(4),
                project: stmt.text(5),
                title: stmt.text(6),
                path: stmt.text(7),
                sidechain: stmt.int(8) != 0,
                snippet: stmt.text(9) ?? "",
                score: stmt.double(10)))
        }
        return hits
    }
}
