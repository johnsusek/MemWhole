# memwhole

Local keyword search over `~/.claude`-style folders: session transcripts, typed prompts, memory notes, skills, file snapshots and config. See `HANDOFF.md` for what gets indexed and why.

```bash
swift build -c release
.build/release/memwhole index ./claude            # incremental; --full rebuilds
.build/release/memwhole search liquid war --role user
.build/release/memwhole show 8b401cde             # read a session from a search hit
.build/release/memwhole stats
```

The index lives at `~/Library/Application Support/MemWhole/index.sqlite`, or wherever `--db` / `$MEMWHOLE_DB` points.

## Search

- Words are ANDed; the last word matches as a prefix. `--raw` passes FTS5 syntax through (`"exact phrase"`, `OR`, `NOT`).
- Filters: `--project TEXT`, `--role user|assistant|tool`, `--kind memory|skill|prompt|snapshot|...`, `--since 2026-10-01` or `--since 7d`, `--limit N`.
- `--json` prints machine-readable hits for a future UI.
- Sub-agent messages, `history.jsonl` prompts (which repeat transcript prompts), snapshots and plugin docs rank lower.

## Layout

| File | Role |
|---|---|
| `Rules.swift` | Path globs to parsers. A new source folder only needs a new `RuleSet`. |
| `Indexer.swift` | Walks the folder, parses changed files, resumes append-only `.jsonl` files from the stored byte offset. |
| `Secrets.swift` | Masks values under `KEY/TOKEN/SECRET/PASSWORD` names and known token shapes before storing. |
| `Schema.swift` | Tables plus FTS5 indexes over `messages.text` and `docs.title/body`. |
| `Search.swift` | One ranked query across both FTS tables. |
