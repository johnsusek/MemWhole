import AppKit

extension AppModel {
  /// Up and down arrows walk the cards from wherever focus is, including while typing in the search field.
  /// The stream has no list to take them and SwiftUI's search field has no key hook, so they're caught on the way in.
  func watchArrowKeys() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let offsets: [UInt16: Int] = [125: 1, 126: -1]
      guard let offset = offsets[event.keyCode], event.modifierFlags.isDisjoint(with: [.shift, .control, .option, .command]) else { return event }

      let isHandled = MainActor.assumeIsolated {
        guard let self, self.isStreamActive, event.window?.isMainWindow == true else { return false }
        self.moveSelection(by: offset)
        return true
      }

      return isHandled ? nil : event
    }
  }
}
