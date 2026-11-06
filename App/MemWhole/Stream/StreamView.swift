import MemWholeKit
import SwiftUI

/// Every note the current search finds as one stack of cards, newest or best first.
struct StreamView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.appearsActive) private var appearsActive

  private struct Row: Identifiable {
    let hit: Hit
    let day: String?
    var id: Hit.ID { hit.id }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          Color.clear.frame(height: 1).id(AppModel.streamStart)

          ForEach(rows) { row in
            VStack(spacing: 12) {
              if let day = row.day {
                Text(day).font(.callout.weight(.medium)).foregroundStyle(.secondary).padding(.top, 8)
              }
              NoteCard(hit: row.hit)
            }
          }

          if model.hasMore { loadOlderRow }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .onChange(of: model.revealTarget) { _, target in
        guard let target else { return }
        proxy.scrollTo(target, anchor: .top)
        model.revealTarget = nil
      }
    }
    .overlay { emptyState }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if model.isIndexing { IndexStatusView() }
    }
    .navigationTitle("Memories")
    .navigationSubtitle(subtitle)
    .onChange(of: appearsActive, initial: true) { _, active in model.isStreamActive = active }
  }

  /// A day label wherever the day changes. Dividers mean nothing in relevance order.
  private var rows: [Row] {
    var rows: [Row] = []
    var previousDay: Date?

    for hit in model.hits {
      let day = model.sort == .date ? Format.parse(hit.ts).map(Calendar.current.startOfDay) : nil
      rows.append(Row(hit: hit, day: day == previousDay ? nil : day.map(label)))
      previousDay = day ?? previousDay
    }

    return rows
  }

  private func label(for day: Date) -> String {
    if Calendar.current.isDateInToday(day) { return "Today" }
    if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(date: .long, time: .omitted)
  }

  private var subtitle: String {
    guard let count = model.total else { return "" }
    let noun = model.query.isBlank ? "note" : "result"
    return count == 1 ? "1 \(noun)" : "\(count.formatted()) \(noun)s"
  }

  @ViewBuilder
  private var emptyState: some View {
    if let error = model.errorMessage {
      ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(error))
    } else if model.hits.isEmpty, model.total == 0 {
      if model.query.isBlank {
        ContentUnavailableView("No Memories", systemImage: "brain", description: Text("Nothing in ~/.claude or ~/.codex/memories yet."))
      } else {
        ContentUnavailableView.search(text: model.query)
      }
    }
  }

  /// Loads the next page when scrolled into view; the button covers a missed appearance.
  private var loadOlderRow: some View {
    HStack {
      if model.isLoadingMore {
        ProgressView().controlSize(.small)
      } else {
        Button("Load More") { model.loadMore() }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .onAppear { model.loadMore() }
  }
}
