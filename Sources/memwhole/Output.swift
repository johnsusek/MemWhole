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
