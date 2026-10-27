import Foundation

/// Masks secret values before anything is stored or shown.
enum Secrets {
    static let mask = "••••••"

    /// `SOME_API_KEY=value`, `"apiToken": "value"`. The value must hold a digit and be 12+ characters,
    /// which keeps code such as `let key = someVariable` readable.
    private static let assignment = try! NSRegularExpression(
        pattern: #"([A-Za-z0-9_.\-]*(?:key|token|secret|password)[A-Za-z0-9_\-]*["']?\s*[:=]\s*["']?)((?=[^\s"',;]*\d)[^\s"',;]{12,})"#,
        options: [.caseInsensitive])

    /// Well-known token shapes, wherever they appear.
    private static let knownToken = try! NSRegularExpression(
        pattern: #"\b(?:sk-[A-Za-z0-9_\-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{35})"#)

    private static let triggers = ["key", "token", "secret", "password", "sk-", "gh", "xox", "akia", "aiza"]

    static func maskText(_ text: String) -> String {
        let lower = text.lowercased()
        guard triggers.contains(where: { lower.contains($0) }) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var result = assignment.stringByReplacingMatches(in: text, range: range, withTemplate: "$1\(mask)")
        result = knownToken.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result), withTemplate: mask)
        return result
    }
}
