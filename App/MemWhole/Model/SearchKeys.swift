import AppKit

extension AppModel {
  /// Up and down arrows in the search field walk the results while typing continues.
  /// SwiftUI's search field offers no hook for this, so the keys are caught on their way to it.
  func watchSearchKeys() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let offsets: [UInt16: Int] = [125: 1, 126: -1]
      guard let offset = offsets[event.keyCode], let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
        editor.isFieldEditor, editor.delegate is NSSearchField
      else { return event }

      MainActor.assumeIsolated { self?.moveSelection(by: offset) }
      return nil
    }
  }
}
