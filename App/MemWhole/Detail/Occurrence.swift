import SwiftUI

/// One match in the open file: the block it sits in (a message, or a run of doc lines) and its order there.
struct Occurrence: Equatable {
    let block: Int64
    let ordinal: Int
}

extension [Occurrence] {
    /// Every match in `blocks`, in reading order.
    init(blocks: [(id: Int64, marked: String?)]) {
        self = blocks.flatMap { block in
            (0..<(block.marked.map { Marks.count(in: $0) } ?? 0)).map { Occurrence(block: block.id, ordinal: $0) }
        }
    }
}

/// Styles matches in marked text with the system find highlight, the current one solid.
func highlightedMatches(_ marked: some StringProtocol, current: Int?) -> AttributedString {
    let highlight = Color(nsColor: .findHighlightColor)
    return Marks.attributed(marked) { match, ordinal in
        match.backgroundColor = ordinal == current ? highlight : highlight.opacity(0.35)
        if ordinal == current { match.foregroundColor = .black }
    }
}
