import MemWholeKit

enum Detail: Sendable {
    /// `marked` holds the full text of each matching message, with matches between `Marks`.
    case session(Store.Session, [Store.Message], focus: Int64?, marked: [Int64: String])
    /// `markedBody` is the body with matches between `Marks`, or nil when the body has none.
    case doc(Store.Doc, markedBody: String?)
}
