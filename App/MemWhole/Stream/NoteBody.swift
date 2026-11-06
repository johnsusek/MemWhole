import AppKit
import MemWholeKit
import SwiftUI

/// A note's text sized to fit, scrolled by the stream around it. Selects its card without giving up text selection.
final class CardTextView: NSTextView {
  var hit: Hit?
  weak var model: AppModel?

  override func mouseDown(with event: NSEvent) {
    if let hit, model?.selection != hit.id { model?.selection = hit.id }
    super.mouseDown(with: event)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event)?.copy() as? NSMenu ?? NSMenu()
    guard let hit, let model else { return menu }

    let items = model.menuItems(for: hit) + [.separator()]
    for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
    model.menuTarget = hit.id
    return menu
  }

  override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
    super.didCloseMenu(menu, with: event)
    model?.menuTarget = nil
  }

  /// Brings a match into the stream's view, with some of the text around it.
  func reveal(_ match: NSRange) {
    guard let layoutManager, let textContainer else { return }
    let glyphs = layoutManager.glyphRange(forCharacterRange: match, actualCharacterRange: nil)
    let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    scrollToVisible(rect.insetBy(dx: 0, dy: -80))
  }
}

struct NoteBody: NSViewRepresentable {
  let hit: Hit
  let model: AppModel
  let rendered: RenderedNote
  /// The match to emphasize, when this card is the selected one.
  let current: Int?
  let revealsMatch: Bool

  func makeNSView(context: Context) -> CardTextView {
    let textView = CardTextView(usingTextLayoutManager: false)
    textView.textContainer?.replaceLayoutManager(InlineCodeLayoutManager())
    textView.isEditable = false
    textView.drawsBackground = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = false
    return textView
  }

  func updateNSView(_ textView: CardTextView, context: Context) {
    guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
    textView.hit = hit
    textView.model = model
    if storage.string != rendered.text.string { storage.setAttributedString(rendered.text) }

    let all = NSRange(location: 0, length: storage.length)
    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
    let highlight = NSColor.findHighlightColor

    for (ordinal, match) in rendered.matches.enumerated() {
      let isCurrent = ordinal == current
      layoutManager.addTemporaryAttribute(.backgroundColor, value: isCurrent ? highlight : highlight.withAlphaComponent(0.35), forCharacterRange: match)
      if isCurrent { layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.black, forCharacterRange: match) }
    }

    guard revealsMatch, let current, rendered.matches.indices.contains(current) else { return }
    let match = rendered.matches[current]

    Task { @MainActor in
      // The stream has to scroll to the card and lay it out first.
      try? await Task.sleep(for: .milliseconds(60))
      textView.reveal(match)
      model.revealsMatch = false
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: CardTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
    container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    return CGSize(width: width, height: ceil(layoutManager.usedRect(for: container).height))
  }
}
