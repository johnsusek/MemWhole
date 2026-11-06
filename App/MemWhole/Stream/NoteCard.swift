import MemWholeKit
import SwiftUI

/// One memory in full. AppKit views underneath take the clicks, drags and right-clicks.
struct NoteCard: View {
  @Environment(AppModel.self) private var model
  @Environment(\.appearsActive) private var appearsActive
  let hit: Hit

  private var isSelected: Bool { model.selection == hit.id }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header.allowsHitTesting(false)
      NoteBody(hit: hit, model: model, rendered: model.rendering(of: hit), current: isSelected ? model.currentMatch : nil, revealsMatch: isSelected && model.revealsMatch)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CardHandle(hit: hit, model: model))
    .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(outlineColor, lineWidth: isSelected || model.menuTarget == hit.id ? 2 : 1)
        .allowsHitTesting(false)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityAction(named: "Select") { model.selection = hit.id }
  }

  private var outlineColor: Color {
    guard isSelected || model.menuTarget == hit.id else { return Color(nsColor: .separatorColor) }
    return appearsActive ? .accentColor : Color(nsColor: .secondaryLabelColor)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(Format.oneLine(hit.title ?? hit.path)).font(.headline)
        Spacer()
        Text(timestamp).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }

      if let project = hit.project {
        Text(Format.path(project)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
    }
  }

  /// In date order the day divider already says which day.
  private var timestamp: String {
    guard let date = Format.parse(hit.ts) else { return Format.date(hit.ts) }
    if model.sort == .date { return date.formatted(date: .omitted, time: .shortened) }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}
