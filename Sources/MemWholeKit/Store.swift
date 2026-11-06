import Foundation

/// Read-side queries shared by the CLI and the app.
public enum Store {
    /// `$MEMWHOLE_DB`, or `~/Library/Application Support/MemWhole/index.sqlite`.
    public static var defaultDatabasePath: String {
        if let path = ProcessInfo.processInfo.environment["MEMWHOLE_DB"] {
            return (path as NSString).expandingTildeInPath
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MemWhole/index.sqlite").path
    }

    public struct Counts: Sendable {
        public var files = 0
        public var notes = 0
        public var sources: [MemorySource: Int] = [:]
        /// Distinct known projects among the notes.
        public var projects = 0
        /// Total size of the notes' text.
        public var bytes: Int64 = 0
    }

    public static func counts(db: Database) throws -> Counts {
        var counts = Counts()
        counts.files = Int(try db.prepare("SELECT COUNT(*) FROM files").scalar() ?? 0)
        let notes = try db.prepare("SELECT COUNT(*), COUNT(DISTINCT project), COALESCE(SUM(LENGTH(body)), 0) FROM notes")
        if try notes.step() {
            counts.notes = notes.int(0)
            counts.projects = notes.int(1)
            counts.bytes = notes.int64(2)
        }

        let sources = try db.prepare("SELECT source, COUNT(*) FROM notes GROUP BY source")

        while try sources.step() {
            if let source = sources.text(0).flatMap(MemorySource.init) { counts.sources[source] = sources.int(1) }
        }

        return counts
    }
}
