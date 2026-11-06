import Foundation

/// A tool whose memories get indexed.
public enum MemorySource: String, CaseIterable, Encodable, Sendable {
  case claude, codex

  public var title: String { rawValue.capitalized }

  public var root: URL {
    let path = self == .claude ? "~/.claude" : "~/.codex/memories"
    return Indexer.resolveFolder(path) ?? URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
  }

  public static var roots: [MemorySource: URL] { Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.root) }) }
}
