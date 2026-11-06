import AppKit
import MemWholeKit
import SwiftUI

/// The card's surface outside its text: click to select, double-click to open, drag out the file, right-click for actions.
final class CardHandleView: NSView, NSDraggingSource {
  var hit: Hit?
  weak var model: AppModel?

  override func mouseDown(with event: NSEvent) {
    guard let hit, let model else { return }
    if model.selection != hit.id { model.selection = hit.id }
    if event.clickCount == 2 { model.open(hit.url) }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let url = hit?.url else { return }
    let item = NSDraggingItem(pasteboardWriter: url as NSURL)
    let location = convert(event.locationInWindow, from: nil)
    let frame = NSRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32)
    item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard let hit, let model else { return nil }
    let menu = NSMenu()
    menu.items = model.menuItems(for: hit)
    model.menuTarget = hit.id
    return menu
  }

  override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
    super.didCloseMenu(menu, with: event)
    model?.menuTarget = nil
  }
}

struct CardHandle: NSViewRepresentable {
  let hit: Hit
  let model: AppModel

  func makeNSView(context: Context) -> CardHandleView { CardHandleView() }

  func updateNSView(_ view: CardHandleView, context: Context) {
    view.hit = hit
    view.model = model
  }
}
