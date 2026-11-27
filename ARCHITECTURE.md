# Architecture

The `MemWholeKit` library holds the index and search. `Sources/memwhole` is the CLI, `App/MemWhole` is the SwiftUI app, and `Tests/` covers the library.

| File | Role |
|---|---|
| `MemorySource.swift` | The sources and where their memories live. |
| `Indexer.swift` | Walks each source, indexes changed notes, and works out each note's project. |
| `CodexMemories.swift` | Splits Codex's `MEMORY.md` into task groups with a project and date. |
| `Secrets.swift` | Masks values under `KEY/TOKEN/SECRET/PASSWORD` names and known token shapes before storing. |
| `Schema.swift` | Tables plus an FTS5 index over `notes.title/body`. |
| `Search.swift` | Ranked or newest-first search, counts and highlighted bodies. |
| `Store.swift` | Note and count lookups shared by the CLI and the app. |
| `Trash.swift` | Moves a Claude note to the Trash and drops its pointer from `MEMORY.md`. |

## Indexing

- Claude: every `projects/*/memory/**/*.md` except `MEMORY.md`, which only lists pointers. Notes are dated by their file's modified time.
- A Claude note's project comes from the first `cwd` in a transcript in the same `projects/<dir>/` folder. Folder names flatten paths lossily (`/` and `.` both become `-`), so without a transcript the name is matched against directories on disk.
- Codex: each `# Task Group:` section of `MEMORY.md` is one note. Its project comes from the `applies_to: cwd=` line, and its date is the newest `rollout_summaries/` filename it cites. `memory_summary.md` and each `extensions/ad_hoc/notes/*.md` are one note apiece.
- A file is re-read only when its size or modified time changes. Files that disappear leave the index.
- The index is a cache: a schema version change deletes and rebuilds it.
