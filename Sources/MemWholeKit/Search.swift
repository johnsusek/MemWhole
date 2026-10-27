import Foundation

public struct SearchOptions: Sendable {
    public var query = ""
    public var limit = 20
    /// Rows to skip, for paging through results.
    public var offset = 0
    public var project: String?
    /// user | assistant. Limits results to transcript messages.
    public var role: String?
    /// Only subagent (sidechain) transcript messages, skipping the main conversation.
    public var sidechainOnly = false
    /// One hit per transcript file, carrying its match count, instead of one per message.
    public var groupByFile = false
    /// Only transcript messages, skipping docs.
    public var messagesOnly = false
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
    /// Source transcript file, for message hits.
    public let fileID: Int64?
    public let role: String          // user | assistant, or the doc kind
    public let ts: String?
    public let project: String?
    public let title: String?
    public let path: String?
    public let sidechain: Bool
    public let snippet: String
    public let score: Double
    /// Matching messages in the file when grouped by file, otherwise 1.
    public let matches: Int
    let groupedByFile: Bool

    /// Unique across both tables. A grouped hit is keyed by its file so it stays selected as the query changes.
    public var id: String {
        if groupedByFile, type == "message", let fileID { return "file-\(fileID)" }
        return "\(type)-\(rowID)"
    }

    func with(snippet: String) -> Hit {
        Hit(type: type, rowID: rowID, sessionID: sessionID, fileID: fileID, role: role, ts: ts, project: project,
            title: title, path: path, sidechain: sidechain, snippet: snippet, score: score, matches: matches,
            groupedByFile: groupedByFile)
    }

    private enum CodingKeys: String, CodingKey {
        case type, rowID, sessionID, fileID, role, ts, project, title, path, sidechain, snippet, score, matches
    }
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

    /// The FTS5 expression for the options' query.
    public static func match(_ options: SearchOptions) -> String {
        options.raw ? options.query : ftsQuery(options.query)
    }

    public static func run(db: Database, options: SearchOptions, marks: (open: String, close: String)) throws -> [Hit] {
        let match = match(options)
        guard !match.isEmpty else { return [] }

        var prefix = ""
        var selects: [String] = []
        var params: [SQLBindable?] = []

        if options.kind == nil {
            let (filter, filterParams) = messageFilter(options, match: match)
            let score = "bm25(messages_fts) * CASE WHEN m.is_sidechain THEN \(sidechainWeight) ELSE 1.0 END"
            let title = "COALESCE(s.custom_title, s.ai_title, s.first_prompt)"

            if options.groupByFile {
                // FTS5 functions can't sit beside window functions, so score the matches first, keep each
                // file's newest (or best) match, and fill in snippets once the page is known.
                let pick = options.sort == .date ? "ts DESC, score, id" : "score, id"
                prefix = """
                    WITH matched AS MATERIALIZED (
                        SELECT m.id, m.file_id, m.session_id, m.role, m.ts, m.is_sidechain, \(score) AS score
                        FROM messages_fts
                        JOIN messages m ON m.id = messages_fts.rowid
                        LEFT JOIN sessions s ON s.id = m.session_id
                        WHERE \(filter)
                    )

                    """
                params += filterParams
                selects.append("""
                    SELECT 'message', g.id, g.session_id, g.role, g.ts, s.project, \(title), NULL, g.is_sidechain,
                           NULL, g.score, g.file_id, g.n
                    FROM (SELECT *, COUNT(*) OVER (PARTITION BY file_id) AS n,
                                 ROW_NUMBER() OVER (PARTITION BY file_id ORDER BY \(pick)) AS rn
                          FROM matched) g
                    LEFT JOIN sessions s ON s.id = g.session_id
                    WHERE g.rn = 1
                    """)
            } else {
                selects.append("""
                    SELECT 'message', m.id, m.session_id, m.role, m.ts, s.project, \(title), NULL, m.is_sidechain,
                           snippet(messages_fts, 0, ?, ?, '…', 24), \(score), m.file_id, 1
                    FROM messages_fts
                    JOIN messages m ON m.id = messages_fts.rowid
                    LEFT JOIN sessions s ON s.id = m.session_id
                    WHERE \(filter)
                    """)
                params += [marks.open, marks.close] + filterParams
            }
        }

        if options.role == nil, !options.messagesOnly {
            let lowKinds = lowKinds.map { "'\($0)'" }.joined(separator: ", ")
            let (filter, filterParams) = docFilter(options, match: match)
            selects.append("""
                SELECT 'doc', d.id, d.session_id, d.kind, d.ts, COALESCE(d.project, s.project),
                       d.title, d.path, 0,
                       snippet(docs_fts, -1, ?, ?, '…', 24),
                       bm25(docs_fts, 4.0, 1.0) * CASE WHEN d.kind IN (\(lowKinds)) THEN \(lowKindWeight) ELSE 1.0 END,
                       NULL, 1
                FROM docs_fts
                JOIN docs d ON d.id = docs_fts.rowid
                LEFT JOIN sessions s ON s.id = d.session_id
                WHERE \(filter)
                """)
            params += [marks.open, marks.close] + filterParams
        }

        let sql = prefix + selects.joined(separator: "\nUNION ALL\n")
            // Row type and id break ties so pages don't overlap or skip rows.
            + (options.sort == .date ? "\nORDER BY 5 DESC, 11, 1, 2" : "\nORDER BY 11, 1, 2")
            + "\nLIMIT ? OFFSET ?"
        params += [options.limit, options.offset]

        let stmt = try db.prepare(sql)
        try stmt.bind(params)
        var hits: [Hit] = []
        while try stmt.step() {
            hits.append(Hit(
                type: stmt.text(0) ?? "",
                rowID: stmt.int64(1),
                sessionID: stmt.text(2),
                fileID: stmt.text(11) == nil ? nil : stmt.int64(11),
                role: stmt.text(3) ?? "",
                ts: stmt.text(4),
                project: stmt.text(5),
                title: stmt.text(6),
                path: stmt.text(7),
                sidechain: stmt.int(8) != 0,
                snippet: stmt.text(9) ?? "",
                score: stmt.double(10),
                matches: stmt.int(12),
                groupedByFile: options.groupByFile))
        }

        if options.groupByFile {
            let ids = hits.filter { $0.type == "message" }.map(\.rowID)
            let snippets = try messageSnippets(db: db, match: match, ids: ids, marks: marks)
            hits = hits.map { hit in
                guard hit.type == "message", let snippet = snippets[hit.rowID] else { return hit }
                return hit.with(snippet: snippet)
            }
        }
        return hits
    }

    /// How many results a search finds in each part of the index, before paging.
    public struct Counts: Sendable {
        /// Matching transcript files when grouped by file, otherwise matching messages.
        public var messages = 0
        /// Matching docs by kind.
        public var docs: [String: Int] = [:]

        public init() {}
    }

    /// Result counts for the options' query across messages and every doc kind, ignoring `kind` and `messagesOnly`
    /// so each scope's total is known at once.
    public static func counts(db: Database, options: SearchOptions) throws -> Counts {
        var counts = Counts()
        let match = match(options)
        guard !match.isEmpty else { return counts }

        let (messageFilter, messageParams) = messageFilter(options, match: match)
        let distinct = options.groupByFile ? "DISTINCT m.file_id" : "*"
        let messages = try db.prepare("""
            SELECT COUNT(\(distinct)) FROM messages_fts
            JOIN messages m ON m.id = messages_fts.rowid
            LEFT JOIN sessions s ON s.id = m.session_id
            WHERE \(messageFilter)
            """)
        try messages.bind(messageParams)
        if try messages.step() { counts.messages = messages.int(0) }

        guard options.role == nil else { return counts }
        var docOptions = options
        docOptions.kind = nil
        let (docFilter, docParams) = docFilter(docOptions, match: match)
        let docs = try db.prepare("""
            SELECT d.kind, COUNT(*) FROM docs_fts
            JOIN docs d ON d.id = docs_fts.rowid
            LEFT JOIN sessions s ON s.id = d.session_id
            WHERE \(docFilter)
            GROUP BY 1
            """)
        try docs.bind(docParams)
        while try docs.step() { counts.docs[docs.text(0) ?? ""] = docs.int(1) }
        return counts
    }

    /// WHERE clause and parameters for matching messages (`m`, joined to sessions `s`).
    private static func messageFilter(_ options: SearchOptions, match: String) -> (String, [SQLBindable?]) {
        var filter = "messages_fts MATCH ? AND \(Store.firstCopy)"
        var params: [SQLBindable?] = [match]
        if let role = options.role { filter += " AND m.role = ?"; params.append(role) }
        if options.sidechainOnly { filter += " AND m.is_sidechain" }
        if let project = options.project { filter += " AND s.project LIKE ?"; params.append("%\(project)%") }
        if let since = options.since { filter += " AND m.ts >= ?"; params.append(since) }
        return (filter, params)
    }

    /// WHERE clause and parameters for matching docs (`d`, joined to sessions `s`).
    private static func docFilter(_ options: SearchOptions, match: String) -> (String, [SQLBindable?]) {
        var filter = "docs_fts MATCH ?"
        var params: [SQLBindable?] = [match]
        if let kind = options.kind { filter += " AND d.kind = ?"; params.append(kind) }
        if let project = options.project {
            filter += " AND COALESCE(d.project, s.project) LIKE ?"
            params.append("%\(project)%")
        }
        if let since = options.since { filter += " AND d.ts >= ?"; params.append(since) }
        return (filter, params)
    }

    private static func messageSnippets(db: Database, match: String, ids: [Int64],
                                        marks: (open: String, close: String)) throws -> [Int64: String] {
        guard !ids.isEmpty else { return [:] }
        let list = ids.map(String.init).joined(separator: ",")
        let stmt = try db.prepare("""
            SELECT rowid, snippet(messages_fts, 0, ?, ?, '…', 24) FROM messages_fts
            WHERE messages_fts MATCH ? AND rowid IN (\(list))
            """)
        try stmt.bind([marks.open, marks.close, match])
        var snippets: [Int64: String] = [:]
        while try stmt.step() { snippets[stmt.int64(0)] = stmt.text(1) ?? "" }
        return snippets
    }

    /// Full text of each matching message in a transcript file, with matches wrapped in `marks`.
    public static func markedMessages(db: Database, match: String, fileID: Int64,
                                      marks: (open: String, close: String)) throws -> [Int64: String] {
        guard !match.isEmpty else { return [:] }
        let stmt = try db.prepare("""
            SELECT rowid, highlight(messages_fts, 0, ?, ?) FROM messages_fts
            WHERE messages_fts MATCH ? AND rowid IN (SELECT id FROM messages WHERE file_id = ?)
            """)
        try stmt.bind([marks.open, marks.close, match, fileID])
        var marked: [Int64: String] = [:]
        while try stmt.step() { marked[stmt.int64(0)] = stmt.text(1) ?? "" }
        return marked
    }

    /// A doc's body with matches wrapped in `marks`, or nil when only the title matches.
    public static func markedBody(db: Database, match: String, docID: Int64,
                                  marks: (open: String, close: String)) throws -> String? {
        guard !match.isEmpty else { return nil }
        let stmt = try db.prepare("""
            SELECT highlight(docs_fts, 1, ?, ?) FROM docs_fts WHERE docs_fts MATCH ? AND rowid = ?
            """)
        try stmt.bind([marks.open, marks.close, match, docID])
        guard try stmt.step(), let body = stmt.text(0), body.contains(marks.open) else { return nil }
        return body
    }
}
