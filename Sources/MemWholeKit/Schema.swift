import Foundation

public enum Schema {
    /// Bump when the tables change. An index with another version is deleted and rebuilt.
    static let version = 5

    static let sql = """
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;

    CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

    -- One row per indexed file, for incremental runs. A Codex MEMORY.md holds many notes.
    CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        size INTEGER NOT NULL,
        mtime REAL NOT NULL
    );

    -- `projects/` folder name (lossy) to the real working directory, from a transcript's `cwd`.
    CREATE TABLE IF NOT EXISTS project_dirs (dir TEXT PRIMARY KEY, project TEXT NOT NULL);

    CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY,
        file_id INTEGER NOT NULL,
        source TEXT NOT NULL,        -- a MemorySource
        path TEXT NOT NULL,
        title TEXT,
        body TEXT NOT NULL,
        project TEXT,
        ts TEXT
    );
    CREATE INDEX IF NOT EXISTS notes_file ON notes(file_id);

    CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
        title, body, content='notes', content_rowid='id',
        tokenize='porter unicode61 remove_diacritics 2'
    );
    CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
        INSERT INTO notes_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
    END;
    CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
    END;
    """

    public static func open(path: String) throws -> Database {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        var db = try Database(path: path)
        let stored = try? db.prepare("SELECT value FROM meta WHERE key = 'schema_version'").scalar()
        if let stored, stored != Int64(version) {
            // The index is a cache of the source folders, so an old layout is rebuilt rather than migrated.
            db = try Database(path: ":memory:")
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
            db = try Database(path: path)
        }
        try db.exec(sql)
        try db.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)").run(String(version))
        return db
    }
}
