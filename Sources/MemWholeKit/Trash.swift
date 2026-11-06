import Foundation

/// Removing memory notes from disk. The index catches up on the next (incremental) run.
public enum Memories {
    /// Moves `note`, a Claude note under `root`, to the Trash and drops its pointer line from
    /// the project's `memory/MEMORY.md`. `trash` stands in for the Trash in tests.
    public static func trash(note: URL, in root: URL,
                             trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        try trash(note)
        try removePointer(to: String(note.path.dropFirst(root.path.count + 1)), in: root)
    }

    /// Drops lines of `projects/<dir>/memory/MEMORY.md` that link to the note, leaving the rest as written.
    static func removePointer(to notePath: String, in root: URL) throws {
        let parts = notePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 3, parts[0] == "projects", parts[2] == "memory" else { return }
        let link = parts.dropFirst(3).joined(separator: "/")
        let index = root.appendingPathComponent(parts.prefix(3).joined(separator: "/")).appendingPathComponent("MEMORY.md")
        guard let text = try? String(contentsOf: index, encoding: .utf8) else { return }

        let targets = ["](\(link))", "](./\(link))"]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { line in !targets.contains { line.contains($0) } }
        guard kept.count != lines.count else { return }
        try kept.joined(separator: "\n").write(to: index, atomically: true, encoding: .utf8)
    }
}
