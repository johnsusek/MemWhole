import Foundation

/// ANSI styling, turned off when the stream is not a terminal.
struct Style {
    let enabled: Bool

    static let stdout = Style(enabled: isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil)

    private func wrap(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    func bold(_ text: String) -> String { wrap(text, "1") }
    func dim(_ text: String) -> String { wrap(text, "2") }
    func cyan(_ text: String) -> String { wrap(text, "36") }
    func yellow(_ text: String) -> String { wrap(text, "33") }
    func magenta(_ text: String) -> String { wrap(text, "35") }

    /// Highlight markers passed to FTS5 `snippet()`.
    var marks: (open: String, close: String) {
        enabled ? ("\u{1B}[1;33m", "\u{1B}[0m") : ("[", "]")
    }
}

enum Format {
    nonisolated(unsafe) private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoParserNoFraction = ISO8601DateFormatter()

    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func date(_ iso: String?) -> String {
        guard let iso else { return "" }
        guard let date = isoParser.date(from: iso) ?? isoParserNoFraction.date(from: iso) else {
            return String(iso.prefix(16))
        }
        return local.string(from: date)
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func path(_ path: String?) -> String {
        guard let path else { return "" }
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    static func shortID(_ id: String?) -> String {
        id.map { String($0.prefix(8)) } ?? ""
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
