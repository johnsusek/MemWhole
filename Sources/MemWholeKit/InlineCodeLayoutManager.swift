import AppKit

public extension NSAttributedString.Key {
  /// A color to shade text with at the height of its font. `.backgroundColor` would fill the whole line, spacing included.
  static let inlineCodeBackground = NSAttributedString.Key("MemWholeInlineCodeBackground")
}

/// Draws `.inlineCodeBackground` under the text and any selection or find highlight.
public final class InlineCodeLayoutManager: NSLayoutManager {
  public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    if let textStorage {
      let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

      textStorage.enumerateAttribute(.inlineCodeBackground, in: characters) { value, range, _ in
        guard let color = value as? NSColor, let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
        color.setFill()
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)

        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, container, lineGlyphs, _ in
          let run = NSIntersectionRange(lineGlyphs, glyphs)
          var box = self.boundingRect(forGlyphRange: run, in: container)
          box.origin.y = fragment.minY + self.location(forGlyphAt: run.location).y - font.ascender
          box.size.height = font.ascender - font.descender
          box.offsetBy(dx: origin.x, dy: origin.y).fill(using: .sourceOver)
        }
      }
    }

    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
  }
}
