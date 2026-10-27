import MemWholeKit

/// Which slice of the index a search covers.
enum Scope: String, CaseIterable, Identifiable {
    case all, transcripts, memory, skills, prompts, snapshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Everything"
        case .transcripts: "Subagent Transcripts"
        case .memory: "Memory"
        case .skills: "Skills"
        case .prompts: "Prompt History"
        case .snapshots: "File Snapshots"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .transcripts: "bubble.left.and.text.bubble.right"
        case .memory: "brain"
        case .skills: "wand.and.stars"
        case .prompts: "clock.arrow.circlepath"
        case .snapshots: "doc.on.doc"
        }
    }

    var kind: String? {
        switch self {
        case .memory: "memory"
        case .skills: "skill"
        case .prompts: "prompt"
        case .snapshots: "snapshot"
        default: nil
        }
    }

    /// Indexed items this scope searches: subagent messages and/or docs.
    func count(in counts: Store.Counts) -> Int {
        let subagentMessages = counts.messages.filter(\.sidechain).reduce(0) { $0 + $1.count }
        switch self {
        case .all: return subagentMessages + counts.docs.reduce(0) { $0 + $1.count }
        case .transcripts: return subagentMessages
        default: return counts.docs.first { $0.kind == kind }?.count ?? 0
        }
    }

    /// Results this scope shows for a search: matching transcripts and/or docs.
    func count(in counts: Search.Counts) -> Int {
        switch self {
        case .all: return counts.messages + counts.docs.values.reduce(0, +)
        case .transcripts: return counts.messages
        default: return kind.flatMap { counts.docs[$0] } ?? 0
        }
    }
}
