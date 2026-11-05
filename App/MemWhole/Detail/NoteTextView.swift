import AppKit
import MemWholeKit
import SwiftUI

/// Runs an action once it has a width, since a match can't be located until the text is laid out.
final class NoteScrollView: NSScrollView {
  var onSized: (() -> Void)?

  override func setFrameSize(_ size: NSSize) {
    super.setFrameSize(size)
    guard size.width > 0, let onSized else { return }
    self.onSized = nil
    onSized()
  }
}

/// The note in one text view, so a selection can run through the whole note.
struct NoteTextView: NSViewRepresentable {
  let rendered: RenderedNote
  let current: Int

  final class Coordinator {
    var scrolledTo: Int?
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NoteScrollView {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.isEditable = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 20, height: 12)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.isVerticallyResizable = true
    textView.autoresizingMask = .width
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    let scrollView = NoteScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NoteScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView, let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
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

    guard rendered.matches.indices.contains(current), context.coordinator.scrolledTo != current else { return }
    let animated = context.coordinator.scrolledTo != nil && !context.environment.accessibilityReduceMotion
    context.coordinator.scrolledTo = current
    let match = rendered.matches[current]
    let scroll = { center(match, in: scrollView, textView: textView, animated: animated) }
    if scrollView.frame.width > 0 { scroll() } else { scrollView.onSized = scroll }
  }

  private func center(_ match: NSRange, in scrollView: NSScrollView, textView: NSTextView, animated: Bool) {
    guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
    layoutManager.ensureLayout(for: container)
    textView.sizeToFit()
    let glyphs = layoutManager.glyphRange(forCharacterRange: match, actualCharacterRange: nil)
    let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
    let clip = scrollView.contentView
    let centered = rect.midY + textView.textContainerOrigin.y - clip.bounds.height / 2
    let origin = NSPoint(x: 0, y: min(max(centered, 0), max(textView.frame.height - clip.bounds.height, 0)))

    if animated {
      NSAnimationContext.runAnimationGroup { _ in clip.animator().setBoundsOrigin(origin) }
    } else {
      clip.setBoundsOrigin(origin)
    }

    scrollView.reflectScrolledClipView(clip)
  }
}
