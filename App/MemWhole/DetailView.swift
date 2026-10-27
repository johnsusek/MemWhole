import MemWholeKit
import SwiftUI

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.detail {
        case .session(let session, let messages, let focus):
            SessionView(session: session, messages: messages, focus: focus)
                .id(session.id)
        case .doc(let doc):
            DocView(doc: doc)
                .id(doc.id)
        case nil:
            ContentUnavailableView("No Selection", systemImage: "text.magnifyingglass",
                                   description: Text("Pick a result to read it in full."))
        }
    }
}

struct SessionView: View {
    let session: Store.Session
    let messages: [Store.Message]
    let focus: Int64?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(messages) { message in
                        MessageView(message: message, isFocus: message.id == focus)
                            .id(message.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if let focus { proxy.scrollTo(focus, anchor: .center) }
            }
        }
        .navigationTitle(session.title.map(Format.oneLine) ?? "Session")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title.map(Format.oneLine) ?? "(untitled)")
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(Format.path(session.project), systemImage: "folder")
                if let branch = session.branch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                Label("\(Format.date(session.firstTS)) → \(Format.date(session.lastTS))", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(session.id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Divider().padding(.top, 8)
        }
    }
}

struct MessageView: View {
    let message: Store.Message
    let isFocus: Bool

    var body: some View {
        if message.role == "tool" {
            Label(Format.path(message.text), systemImage: "wrench.and.screwdriver")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(4)
                .background(isFocus ? Color.yellow.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoleBadge(role: message.role)
                    if message.sidechain {
                        Text("agent").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(Format.date(message.ts)).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isFocus {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.7), lineWidth: 1.5)
                }
            }
        }
    }

    private var background: Color {
        message.role == "user" ? Color.blue.opacity(0.07) : Color.secondary.opacity(0.06)
    }
}

struct DocView: View {
    @Environment(AppModel.self) private var model
    let doc: Store.Doc

    /// Very large docs (the changelog) make a single Text view slow.
    private static let displayLimit = 200_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        RoleBadge(role: doc.kind, isDoc: true)
                        Text(Format.date(doc.ts)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(doc.title ?? doc.path).font(.title2.weight(.semibold)).textSelection(.enabled)
                    if let project = doc.project {
                        Label(Format.path(project), systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(doc.path).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                }
                Divider()
                Text(doc.body.count > Self.displayLimit ? String(doc.body.prefix(Self.displayLimit)) + "\n\n…" : doc.body)
                    .font(isCode ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .navigationTitle(doc.title ?? doc.path)
        .toolbar {
            ToolbarItem {
                Button("Show in Finder", systemImage: "folder") { model.revealInFinder(doc) }
                    .disabled(model.folderPath == nil || doc.kind == "prompt")
            }
        }
    }

    private var isCode: Bool {
        ["snapshot", "config", "plugin-manifest"].contains(doc.kind)
    }
}
