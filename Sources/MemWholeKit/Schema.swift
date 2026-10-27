import Foundation

public enum Schema {
    static let version = 1

    static let sql = """
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;

    CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

    -- One row per indexed source file, for incremental runs.
    CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        size INTEGER NOT NULL,
        mtime REAL NOT NULL,
        offset INTEGER NOT NULL DEFAULT 0,
        parser TEXT NOT NULL
    );

    -- Transcript folder name (lossy) to the real working directory, from records' `cwd`.
    CREATE TABLE IF NOT EXISTS project_dirs (dir TEXT PRIMARY KEY, project TEXT NOT NULL);

    CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        project TEXT,
        custom_title TEXT,
        ai_title TEXT,
        first_prompt TEXT,
        branch TEXT,
        first_ts TEXT,
        last_ts TEXT
    );

    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY,
        file_id INTEGER NOT NULL,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,          -- user | assistant | tool
        ts TEXT,
        text TEXT NOT NULL,
        tool_name TEXT,
        file_path TEXT,
        is_sidechain INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS messages_session ON messages(session_id, ts);
    CREATE INDEX IF NOT EXISTS messages_file ON messages(file_id);

    CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
        text, content='messages', content_rowid='id',
        tokenize='porter unicode61 remove_diacritics 2'
    );
    CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
        INSERT INTO messages_fts(rowid, text) VALUES (new.id, new.text);
    END;
    CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
        INSERT INTO messages_fts(messages_fts, rowid, text) VALUES ('delete', old.id, old.text);
    END;

    CREATE TABLE IF NOT EXISTS docs (
        id INTEGER PRIMARY KEY,
        file_id INTEGER NOT NULL,
        source TEXT NOT NULL,
        path TEXT NOT NULL,          -- relative to the source root
        kind TEXT NOT NULL,
        title TEXT,
        body TEXT NOT NULL,
        project TEXT,
        session_id TEXT,
        ts TEXT
    );
    CREATE INDEX IF NOT EXISTS docs_file ON docs(file_id);

    CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
        title, body, content='docs', content_rowid='id',
        tokenize='porter unicode61 remove_diacritics 2'
    );
    CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON docs BEGIN
        INSERT INTO docs_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
    END;
    CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON docs BEGIN
        INSERT INTO docs_fts(docs_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
    END;
    """

    public static func open(path: String) throws -> Database {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        let db = try Database(path: path)
        try db.exec(sql)
        try db.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)").run(String(version))
        return db
    }
}
