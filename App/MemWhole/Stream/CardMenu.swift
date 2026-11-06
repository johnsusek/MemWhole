import AppKit
import MemWholeKit

/// A menu item that runs a closure. A disabled one has no action, so menus that validate their items gray it out.
@MainActor
final class ActionMenuItem: NSMenuItem {
  private let run: @MainActor () -> Void

  init(_ title: String, enabled: Bool = true, run: @escaping @MainActor () -> Void) {
    self.run = run
    super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) { fatalError("Not used from a nib") }

  @objc private func fire() { run() }
}

extension AppModel {
  /// A card's context menu, which acts on that card whether or not it's selected.
  func menuItems(for hit: Hit) -> [NSMenuItem] {
    var items: [NSMenuItem] = [
      ActionMenuItem("Open") { [self] in open(hit.url) },
      ActionMenuItem("Show in Finder") { [self] in reveal(hit.url) },
      .separator(),
    ]

    if let title = hit.title, !title.isBlank {
      items.append(ActionMenuItem("Copy Title") { [self] in copy(Format.oneLine(title)) })
    }

    items.append(ActionMenuItem("Copy Path") { [self] in copy(hit.path) })
    items.append(ActionMenuItem("Copy Note") { [self] in copy(Marks.stripped(hit.body)) })
    items.append(.separator())
    items.append(ActionMenuItem("Move to Trash", enabled: canTrash(hit)) { [self] in trash(hit) })
    return items
  }
}
