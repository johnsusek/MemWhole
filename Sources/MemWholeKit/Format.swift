import Foundation

public enum Format {
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

    public static func date(_ iso: String?) -> String {
        guard let iso else { return "" }
        guard let date = isoParser.date(from: iso) ?? isoParserNoFraction.date(from: iso) else {
            return String(iso.prefix(16))
        }
        return local.string(from: date)
    }

    public static let home = FileManager.default.homeDirectoryForCurrentUser.path

    public static func path(_ path: String?) -> String {
        guard let path else { return "" }
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    public static func shortID(_ id: String?) -> String {
        id.map { String($0.prefix(8)) } ?? ""
    }

    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
