import Foundation

/// Highlight markers around FTS5 matches in snippets and marked text.
enum Marks {
    static let open = "\u{1}"
    static let close = "\u{2}"

    static func count(in marked: some StringProtocol) -> Int {
        marked.components(separatedBy: open).count - 1
    }

    /// The text without markers, with `style` applied to each match along with its order in the text.
    static func attributed(_ marked: some StringProtocol, style: (inout AttributedString, Int) -> Void) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(marked)
        var ordinal = 0
        while let open = rest.range(of: open) {
            result += AttributedString(rest[..<open.lowerBound])
            rest = rest[open.upperBound...]
            let close = rest.range(of: close) ?? rest.endIndex..<rest.endIndex
            var match = AttributedString(rest[..<close.lowerBound])
            style(&match, ordinal)
            ordinal += 1
            result += match
            rest = rest[close.upperBound...]
        }
        result += AttributedString(rest)
        return result
    }
}
