import Foundation

/// How a matched file is turned into index rows.
public enum ParserKind: String, Sendable {
    case transcript       // Claude Code session .jsonl, one row per message block
    case history          // history.jsonl, one doc per typed prompt
    case markdown         // full text, frontmatter name/description as title
    case json             // pretty-printed with secret values masked
    case snapshot         // file-history/<session>/<hash>@vN, latest version only
    case skip
}

public struct Rule {
    let glob: String
    let parser: ParserKind
    /// Doc kind shown in results (memory, skill, config...).
    let kind: String
    let sidechain: Bool
    /// A skip rule whose whole directory can be left without walking it.
    let prune: Bool
    let regex: NSRegularExpression

    init(_ glob: String, _ parser: ParserKind, kind: String = "", sidechain: Bool = false, prune: Bool = false) {
        self.glob = glob
        self.parser = parser
        self.kind = kind
        self.sidechain = sidechain
        self.prune = prune
        self.regex = Rule.compile(glob)
    }

    func matches(_ relativePath: String) -> Bool {
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return regex.firstMatch(in: relativePath, range: range) != nil
    }

    /// `**/` matches zero or more folders, `**` anything, `*` and `?` stay within one path part.
    static func compile(_ glob: String) -> NSRegularExpression {
        var pattern = "^"
        var chars = Array(glob)[...]
        while let c = chars.popFirst() {
            switch c {
            case "*" where chars.first == "*":
                chars.removeFirst()
                if chars.first == "/" {
                    chars.removeFirst()
                    pattern += "(?:.*/)?"
                } else {
                    pattern += ".*"
                }
            case "*": pattern += "[^/]*"
            case "?": pattern += "[^/]"
            default: pattern += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        return try! NSRegularExpression(pattern: pattern + "$")
    }
}

/// Rule set for one source folder. First match wins; unmatched files are skipped.
public struct RuleSet {
    let source: String
    let rules: [Rule]

    func rule(for relativePath: String) -> Rule? {
        rules.first { $0.matches(relativePath) }
    }

    /// True when nothing under `relativeDir` can be indexed.
    func prunes(directory relativeDir: String) -> Bool {
        let probe = relativeDir + "/\u{1}"
        guard let rule = rule(for: probe) else { return false }
        return rule.parser == .skip && rule.prune
    }

    nonisolated(unsafe) public static let claude = RuleSet(source: "claude", rules: [
        // Never index
        Rule("**/*.key", .skip),
        Rule("**/.git/**", .skip, prune: true),
        Rule("**/tool-results/**", .skip, prune: true),
        Rule("**/scripts/**", .skip, prune: true),
        Rule("**/node_modules/**", .skip, prune: true),
        Rule("session-env/**", .skip, prune: true),
        Rule("sessions/**", .skip, prune: true),
        Rule("jobs/**", .skip, prune: true),
        Rule("daemon/**", .skip, prune: true),
        Rule("ide/**", .skip, prune: true),
        Rule("telemetry/**", .skip, prune: true),
        Rule("backups/**", .skip, prune: true),
        Rule("debug/**", .skip, prune: true),
        Rule("paste-cache/**", .skip, prune: true),
        Rule("plugins/cache/**", .skip, prune: true),
        Rule("cache/changelog.md", .markdown, kind: "changelog"),
        Rule("cache/**", .skip),

        // Transcripts
        Rule("projects/*/*.jsonl", .transcript),
        Rule("projects/*/*/subagents/**/*.jsonl", .transcript, sidechain: true),
        Rule("projects/*/memory/**/*.md", .markdown, kind: "memory"),

        // Other text
        Rule("history.jsonl", .history, kind: "prompt"),
        Rule("file-history/*/*", .snapshot, kind: "snapshot"),
        Rule("skills/**/*.md", .markdown, kind: "skill"),
        Rule("scheduled-tasks/*/SKILL.md", .markdown, kind: "task"),
        Rule("CLAUDE.md", .markdown, kind: "rules"),
        Rule("settings.json", .json, kind: "config"),
        Rule("plugins/marketplaces/**/*.md", .markdown, kind: "plugin-doc"),
        Rule("plugins/synced/**/*.md", .markdown, kind: "plugin-doc"),
        Rule("plugins/marketplaces/**/plugin.json", .json, kind: "plugin-manifest"),
        Rule("plugins/marketplaces/**/marketplace.json", .json, kind: "plugin-manifest"),
        Rule("plugins/synced/**/plugin.json", .json, kind: "plugin-manifest"),
        Rule("plugins/synced/**/marketplace.json", .json, kind: "plugin-manifest"),
    ])
}
