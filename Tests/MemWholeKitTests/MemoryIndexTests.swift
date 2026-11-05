import Foundation
import Testing
@testable import MemWholeKit

/// A throwaway `~/.claude`-style folder and index for one test.
private struct Fixture {
    let root: URL
    let databasePath: String

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("memwhole-tests-\(UUID().uuidString)", isDirectory: true)
        let folder = base.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        root = try #require(Indexer.resolveFolder(folder.path))
        databasePath = base.appendingPathComponent("index.sqlite").path
    }

    func write(_ relativePath: String, _ text: String, modified: Date? = nil) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    func remove(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(relativePath))
    }

    @discardableResult
    func index() throws -> IndexStats {
        try Indexer.index(folder: root, databasePath: databasePath, full: false) { _ in }
    }

    func search(_ query: String = "", sort: SearchSort = .date) throws -> [Hit] {
        var options = SearchOptions()
        options.query = query
        options.limit = 100
        options.sort = sort
        return try Search.run(db: Schema.open(path: databasePath), options: options, marks: ("[", "]"))
    }
}

@Suite struct MemoryIndexTests {
    @Test func indexesOnlyMemoryNotes() throws {
        let f = try Fixture()
        try f.write("projects/-Users-me-App/memory/build.md", "---\nname: build-steps\n---\nRun the release build.")
        try f.write("projects/-Users-me-App/memory/MEMORY.md", "- [Build](build.md) — release build")
        try f.write("projects/-Users-me-App/abc.jsonl",
                    #"{"type":"user","sessionId":"abc","cwd":"/Users/me/App","message":{"content":"release build please"}}"# + "\n")
        try f.write("history.jsonl", #"{"display":"release build","timestamp":1}"# + "\n")
        try f.write("skills/ship/SKILL.md", "# Ship\nrelease build")
        try f.write("CLAUDE.md", "release build rules")
        try f.write("file-history/abc/123@v1", "release build snapshot")
        try f.index()

        let hits = try f.search("release")
        #expect(hits.count == 1)
        #expect(hits.first?.title == "build-steps")
        #expect(hits.first?.path == "projects/-Users-me-App/memory/build.md")

        let counts = try Store.counts(db: Schema.open(path: f.databasePath))
        #expect(counts.notes == 1)
        #expect(counts.files == 1)
    }

    @Test func takesProjectFromTranscriptCwd() throws {
        let f = try Fixture()
        try f.write("projects/-Users-me-My-App/memory/a.md", "# A\nbody")
        try f.write("projects/-Users-me-My-App/s1.jsonl",
                    #"{"type":"summary"}"# + "\n" + #"{"type":"user","cwd":"/Users/me/My-App","sessionId":"s1"}"# + "\n")
        try f.write("projects/-Users-me-Other/memory/b.md", "# B\nbody")
        try f.index()

        let hits = try f.search()
        #expect(hits.first { $0.title == "A" }?.project == "/Users/me/My-App")
        #expect(hits.first { $0.title == "B" }?.project == nil)
    }

    @Test func fallsBackToExistingDirectoryForFolderName() throws {
        let f = try Fixture()
        let real = f.root.deletingLastPathComponent().appendingPathComponent("My-App.v2/src")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let flattened = real.path.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        try f.write("projects/\(flattened)/memory/a.md", "# A\nbody")
        try f.index()

        #expect(try f.search().first?.project == real.path)
        #expect(Indexer.existingPath(flattened: "-no-such-place-here") == nil)
    }

    @Test func blankSearchListsEveryNoteNewestFirst() throws {
        let f = try Fixture()
        let now = Date()
        try f.write("projects/-p/memory/old.md", "# Old\nx", modified: now.addingTimeInterval(-3600))
        try f.write("projects/-p/memory/new.md", "# New\ny", modified: now)
        try f.write("projects/-p/memory/mid.md", "# Mid\nz", modified: now.addingTimeInterval(-60))
        try f.index()

        #expect(try f.search().map(\.title) == ["New", "Mid", "Old"])
        var options = SearchOptions()
        #expect(try Search.count(db: Schema.open(path: f.databasePath), options: options) == 3)
        options.query = "y"
        #expect(try Search.count(db: Schema.open(path: f.databasePath), options: options) == 1)
    }

    @Test func queryMarksMatchesInSnippetAndBody() throws {
        let f = try Fixture()
        try f.write("projects/-p/memory/n.md", "# Note\nThe sqlite index lives here.")
        try f.index()

        let hit = try #require(try f.search("sqlite").first)
        #expect(hit.snippet.contains("[sqlite]"))
        let db = try Schema.open(path: f.databasePath)
        let body = try Search.markedBody(db: db, match: Search.ftsQuery("sqlite"), noteID: hit.id, marks: ("[", "]"))
        #expect(body?.contains("[sqlite] index") == true)
        #expect(try Store.note(db: db, id: hit.id)?.title == "Note")
    }

    @Test func dropsNotesWhoseFilesAreGone() throws {
        let f = try Fixture()
        try f.write("projects/-p/memory/a.md", "# A\nx")
        try f.write("projects/-p/memory/b.md", "# B\nx")
        try f.index()
        try f.remove("projects/-p/memory/a.md")
        let stats = try f.index()

        #expect(stats.removed == 1)
        #expect(try f.search().map(\.title) == ["B"])
    }

    @Test func masksSecrets() throws {
        let f = try Fixture()
        try f.write("projects/-p/memory/k.md", "# Keys\nOPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456")
        try f.index()

        let note = try #require(try Store.note(db: Schema.open(path: f.databasePath), id: f.search().first!.id))
        #expect(!note.body.contains("sk-abcdefghijklmnopqrstuvwxyz123456"))
    }
}

@Suite struct TrashTests {
    @Test func trashesNoteAndItsPointer() throws {
        let f = try Fixture()
        try f.write("projects/-Users-me-App/memory/build.md", "---\nname: build-steps\n---\nRun the release build.")
        try f.write("projects/-Users-me-App/memory/keep.md", "---\nname: keep\n---\nStays.")
        try f.write("projects/-Users-me-App/memory/MEMORY.md",
                    "- [Build](build.md) — release build\n- [Keep](keep.md) — stays\n")
        try f.index()

        var trashed: [URL] = []
        try Memories.trash(notePath: "projects/-Users-me-App/memory/build.md", in: f.root) {
            trashed.append($0)
            try FileManager.default.removeItem(at: $0)
        }
        #expect(trashed.map(\.lastPathComponent) == ["build.md"])

        let index = try String(contentsOf: f.root.appendingPathComponent("projects/-Users-me-App/memory/MEMORY.md"), encoding: .utf8)
        #expect(index == "- [Keep](keep.md) — stays\n")

        #expect(try f.index().removed == 1)
        #expect(try f.search().map(\.title) == ["keep"])
    }

    @Test func trashesNoteInSubfolderWithoutIndexFile() throws {
        let f = try Fixture()
        try f.write("projects/-Users-me-App/memory/topics/a.md", "# A\nbody")
        try f.index()

        try Memories.trash(notePath: "projects/-Users-me-App/memory/topics/a.md", in: f.root) {
            try FileManager.default.removeItem(at: $0)
        }
        try f.index()
        #expect(try f.search().isEmpty)
    }

    @Test func failedTrashLeavesPointer() throws {
        let f = try Fixture()
        try f.write("projects/-Users-me-App/memory/MEMORY.md", "- [Gone](gone.md) — missing\n")
        struct Failure: Error {}
        #expect(throws: Failure.self) {
            try Memories.trash(notePath: "projects/-Users-me-App/memory/gone.md", in: f.root) { _ in throw Failure() }
        }
        let index = try String(contentsOf: f.root.appendingPathComponent("projects/-Users-me-App/memory/MEMORY.md"), encoding: .utf8)
        #expect(index == "- [Gone](gone.md) — missing\n")
    }
}

@Suite struct NoteRendererTests {
  private let marks = (open: "\u{1}", close: "\u{2}")

  private func rendered(_ source: String) -> RenderedNote { NoteRenderer.render(source, marks: marks) }

  @Test func dropsFrontmatterAndMarkup() {
    let note = rendered("---\nname: x\n---\n\n# Title\n\nSome **bold** and `code` words\nwrapped.\n\n- one\n- two\n")
    #expect(note.text.string == "Title\nSome bold and code words wrapped.\n\u{2022}\tone\n\u{2022}\ttwo")
  }

  @Test func matchesLandOnTheRenderedText() {
    let note = rendered("# \u{1}alpha\u{2}\n\nSee **\u{1}beta\u{2}** and `\u{1}gamma\u{2}`.\n\n```\n\u{1}delta\u{2}\n```\n")
    let found = note.matches.map { (note.text.string as NSString).substring(with: $0) }
    #expect(found == ["alpha", "beta", "gamma", "delta"])
    #expect(!note.text.string.contains("\u{1}"))
    #expect(!note.text.string.contains("\u{2}"))
  }

  @Test func aMatchInAHiddenURLIsDropped() {
    let note = rendered("[docs](https://\u{1}example\u{2}.com) and https://\u{1}example\u{2}.org/page\n")
    #expect(note.text.string == "docs and https://example.org/page")
    #expect(note.matches == [NSRange(location: 17, length: 7)])
    #expect(note.text.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
  }

  @Test func onlyWebLinksAreClickable() {
    let web = rendered("[a](https://example.com)")
    let local = rendered("[a](file:///Applications/Calculator.app)")
    #expect(web.text.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    #expect(local.text.attribute(.link, at: 0, effectiveRange: nil) == nil)
  }

  @Test func tablesLineUp() {
    let note = rendered("| a | bee |\n|---|---|\n| \u{1}cc\u{2} | d |\n")
    #expect(note.text.string == "a   bee\ncc  d  ")
    #expect(note.matches == [NSRange(location: 8, length: 2)])
  }
}
