import Foundation

/// Markers around FTS5 matches in marked text.
enum Marks {
  static let open = "\u{1}"
  static let close = "\u{2}"

  static func stripped(_ marked: String) -> String {
    marked.replacingOccurrences(of: open, with: "").replacingOccurrences(of: close, with: "")
  }
}
