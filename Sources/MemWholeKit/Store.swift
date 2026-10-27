import Foundation

/// Read-side queries shared by the CLI and the app.
public enum Store {
    /// SQL condition on messages aliased `m`: true for the first stored copy of a record.
    static let firstCopy = """
        NOT EXISTS (SELECT 1 FROM messages earlier WHERE earlier.record_id = m.record_id AND earlier.id < m.id)
        """

    /// `$MEMWHOLE_DB`, or `~/Library/Application Support/MemWhole/index.sqlite`.
    public static var defaultDatabasePath: String {
        if let path = ProcessInfo.processInfo.environment["MEMWHOLE_DB"] {
            return (path as NSString).expandingTildeInPath
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MemWhole/index.sqlite").path
    }

    public struct Session: Sendable {
        public let id: String
        public let project: String?
        public let title: String?
        public let branch: String?
        public let firstTS: String?
        public let lastTS: String?
    }

    public struct Message: Sendable, Identifiable {
        public let id: Int64
        public let role: String
        public let ts: String?
        public let text: String
        public let sidechain: Bool
    }

    public struct Doc: Sendable {
        public let id: Int64
        public let kind: String
        public let path: String
        public let title: String?
        public let body: String
        public let project: String?
        public let ts: String?
    }

    public struct Counts: Sendable {
        public var sessions = 0
        public var files = 0
        /// (role, sidechain, count), largest first.
        public var messages: [(role: String, sidechain: Bool, count: Int)] = []
        /// (kind, count, bytes), largest first.
        public var docs: [(kind: String, count: Int, bytes: Int64)] = []
    }

    /// Sessions whose id starts with `prefix`, most recent first (at most 5).
    public static func sessions(db: Database, idPrefix prefix: String) throws -> [Session] {
        let stmt = try db.prepare("""
            SELECT id, project, COALESCE(custom_title, ai_title, first_prompt), branch, first_ts, last_ts
            FROM sessions WHERE id LIKE ? || '%' ORDER BY last_ts DESC LIMIT 5
            """)
        try stmt.bind([prefix])
        var sessions: [Session] = []
        while try stmt.step() {
            sessions.append(Session(
                id: stmt.text(0) ?? "", project: stmt.text(1), title: stmt.text(2), branch: stmt.text(3),
                firstTS: stmt.text(4), lastTS: stmt.text(5)))
        }
        return sessions
    }

    public static func messages(db: Database, sessionID: String, includeSidechain: Bool) throws -> [Message] {
        let stmt = try db.prepare("""
            SELECT m.id, m.role, m.ts, m.text, m.is_sidechain FROM messages m
            WHERE m.session_id = ? AND (? OR m.is_sidechain = 0) AND \(firstCopy)
            ORDER BY m.ts, m.id
            """)
        try stmt.bind([sessionID, includeSidechain])
        var messages: [Message] = []
        while try stmt.step() {
            messages.append(Message(
                id: stmt.int64(0), role: stmt.text(1) ?? "", ts: stmt.text(2), text: stmt.text(3) ?? "",
                sidechain: stmt.int(4) != 0))
        }
        return messages
    }

    public static func doc(db: Database, id: Int64) throws -> Doc? {
        let stmt = try db.prepare("""
            SELECT d.id, d.kind, d.path, d.title, d.body, COALESCE(d.project, s.project), d.ts
            FROM docs d LEFT JOIN sessions s ON s.id = d.session_id WHERE d.id = ?
            """)
        try stmt.bind([id])
        guard try stmt.step() else { return nil }
        return Doc(
            id: stmt.int64(0), kind: stmt.text(1) ?? "", path: stmt.text(2) ?? "", title: stmt.text(3),
            body: stmt.text(4) ?? "", project: stmt.text(5), ts: stmt.text(6))
    }

    public static func counts(db: Database) throws -> Counts {
        var counts = Counts()
        counts.sessions = Int(try db.prepare("SELECT COUNT(*) FROM sessions").scalar() ?? 0)
        counts.files = Int(try db.prepare("SELECT COUNT(*) FROM files").scalar() ?? 0)

        let roles = try db.prepare(
            "SELECT role, is_sidechain, COUNT(*) FROM messages m WHERE \(firstCopy) GROUP BY 1, 2 ORDER BY 3 DESC")
        while try roles.step() {
            counts.messages.append((roles.text(0) ?? "", roles.int(1) != 0, roles.int(2)))
        }
        let kinds = try db.prepare("SELECT kind, COUNT(*), SUM(LENGTH(body)) FROM docs GROUP BY 1 ORDER BY 2 DESC")
        while try kinds.step() {
            counts.docs.append((kinds.text(0) ?? "", kinds.int(1), kinds.int64(2)))
        }
        return counts
    }
}
