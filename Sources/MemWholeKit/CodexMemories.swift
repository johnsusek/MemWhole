import Foundation

/// A note ready for the index. Without a `ts`, it takes its file's modified time.
struct Note: Equatable {
  var title: String
  var body: String
  var project: String?
  var ts: String?
}

/// Reads the task groups Codex consolidates into `MEMORY.md`.
enum CodexMemories {
  private static let heading = "# Task Group: "

  /// One note per `# Task Group:` section, without its heading, which the card already shows as the title.
  static func taskGroups(in text: String) -> [Note] {
    var sections: [(title: String, lines: [Substring])] = []

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix(heading) {
        sections.append((String(line.dropFirst(heading.count)), []))
      } else if !sections.isEmpty {
        sections[sections.count - 1].lines.append(line)
      }
    }

    return sections.map { section in
      let body = section.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      return Note(title: section.title, body: body, project: project(in: body), ts: newestRollout(in: body))
    }
  }

  /// The path in an `applies_to: cwd=` line. Some name several projects in words instead, which gives nil.
  static func project(in body: String) -> String? {
    body.firstMatch(of: #/(?m)^applies_to: cwd=(/[^\s;]+)/#).map { String($0.1) }
  }

  /// The newest UTC stamp among cited `rollout_summaries/` filenames. `MEMORY.md`'s own modified time won't do:
  /// each consolidation rewrites the file, which would put every group at the same moment.
  static func newestRollout(in body: String) -> String? {
    body.matches(of: #/rollout_summaries/(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})/#)
      .map { "\($0.1)T\($0.2):\($0.3):\($0.4).000Z" }
      .max()
  }
}
