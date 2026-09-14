import AppKit
import GobblCore
import SwiftUI

enum MemorySection: Hashable {
    case todos, timeline, people, projects, orgs, topics, search
}

@MainActor @Observable
final class MemoryNav {
    static let shared = MemoryNav()
    var section: MemorySection = .todos
}

/// "Gobbl Memory": to-dos, people and the rest of the knowledge base, and search.
@MainActor
enum MemoryWindow {
    private static var window: NSWindow?

    static func show(_ section: MemorySection = .todos) {
        MemoryNav.shared.section = section
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Gobbl Memory"
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentViewController = NSHostingController(rootView: MemoryView())
            w.setContentSize(NSSize(width: 960, height: 640))
            w.center()
            w.setFrameAutosaveName("GobblMemory")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        KnowledgeCenter.shared.process()
        TodoCenter.shared.reload()
    }
}

struct MemoryView: View {
    @State private var nav = MemoryNav.shared
    @State private var selection: MemorySection? = .todos
    @State private var memory = MemoryModel.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("To-dos", systemImage: "checklist").tag(MemorySection.todos)
                Label("Timeline", systemImage: "calendar.day.timeline.left").tag(MemorySection.timeline)
                Section("Knowledge") {
                    Label("People", systemImage: "person.2").tag(MemorySection.people)
                    Label("Projects", systemImage: "folder").tag(MemorySection.projects)
                    Label("Organisations", systemImage: "building.2").tag(MemorySection.orgs)
                    Label("Topics", systemImage: "number").tag(MemorySection.topics)
                }
                Label("Search", systemImage: "magnifyingglass").tag(MemorySection.search)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                if !memory.enabled {
                    ContentUnavailableView {
                        Label("Memory is off", systemImage: "brain")
                    } description: {
                        Text("Turn it on in Settings → Memory. Gobbl reads the text in the apps you use, never screenshots, and keeps it on this Mac.")
                    } actions: {
                        Button("Open Settings") { AppActions.openSettings() }
                    }
                } else {
                    switch selection ?? .todos {
                    case .todos: TodosPane()
                    case .timeline: TimelinePane()
                    case .people: EntitiesPane(type: .person)
                    case .projects: EntitiesPane(type: .project)
                    case .orgs: EntitiesPane(type: .org)
                    case .topics: EntitiesPane(type: .topic)
                    case .search: SearchPane()
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 440)
        }
        .onAppear { selection = nav.section }
        .onChange(of: nav.section) { _, value in selection = value }
    }
}

// MARK: To-dos

private struct TodosPane: View {
    @State private var todos = TodoCenter.shared

    var body: some View {
        List {
            Section("To do") {
                if todos.open.isEmpty {
                    Text("Nothing yet. Gobbl suggests to-dos from your chats, mail and unfinished checkouts, about every half hour.")
                        .foregroundStyle(.secondary)
                }
                ForEach(todos.open) { TodoRow(todo: $0) }
            }
            if !todos.maybe.isEmpty {
                Section("Maybe") { ForEach(todos.maybe) { TodoRow(todo: $0) } }
            }
            if !todos.autoDone.isEmpty {
                Section("Ticked off automatically") {
                    ForEach(todos.autoDone) { t in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(t.title)
                            Spacer()
                            if let at = t.resolvedAt { Text(at.formatted(.relative(presentation: .named))).foregroundStyle(.secondary) }
                            Button("Undo") { todos.undo(t) }
                        }
                    }
                }
            }
        }
        .toolbar {
            Button {
                Task { await todos.extract() }
            } label: {
                Label("Check Now", systemImage: todos.extracting ? "hourglass" : "arrow.clockwise")
            }
            .help("Look for new to-dos in what Gobbl saw recently")
            .disabled(todos.extracting)
        }
    }
}

// MARK: People, projects, organisations, topics

private struct EntitiesPane: View {
    let type: EntityType
    @State private var query = ""
    @State private var everyone = false
    @State private var items: [EntitySummary] = []
    @State private var selected: Int64?
    @State private var kb = KnowledgeCenter.shared

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if type == .person { MergeBanner() }
                HStack {
                    TextField("Search \(type.title.lowercased())", text: $query).textFieldStyle(.roundedBorder)
                    if type == .person {
                        Toggle("Everyone", isOn: $everyone).toggleStyle(.checkbox)
                            .help("Also show people seen only once in the last 30 days")
                    }
                }
                .padding(8)
                List(items, selection: $selected) { e in
                    EntityRow(entity: e).tag(e.id)
                }
                .overlay {
                    if items.isEmpty {
                        Text(query.isEmpty ? "No \(type.title.lowercased()) yet. They appear as Gobbl sees them in chats and mail." : "No matches")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            Group {
                if let selected {
                    EntityCardView(id: selected) { self.selected = $0 }.id(selected)
                } else {
                    ContentUnavailableView("Pick one to see what Gobbl knows", systemImage: type == .person ? "person.crop.circle" : "folder")
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(type.rawValue)|\(query)|\(everyone)|\(kb.version)") { load() }
    }

    private func load() {
        guard let store = MemoryModel.shared.store else {
            items = []
            return
        }
        items = (try? store.entities(type, matching: query, everyone: everyone)) ?? []
    }
}

private struct EntityRow: View {
    let entity: EntitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(entity.name).font(.system(size: 13, weight: .semibold))
                if entity.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            let subtitle = [entity.role, entity.org].compactMap { $0 }.joined(separator: " · ")
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1) }
            HStack(spacing: 4) {
                if let seen = entity.lastSeen { Text("Seen \(seen.formatted(.relative(presentation: .named)))") }
                if !entity.apps.isEmpty { Text("· " + entity.apps.prefix(3).joined(separator: ", ")) }
            }
            .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct MergeBanner: View {
    @State private var kb = KnowledgeCenter.shared

    var body: some View {
        if let s = kb.suggestions.first {
            VStack(alignment: .leading, spacing: 6) {
                Label("Same person?", systemImage: "person.2.badge.gearshape").font(.headline)
                Text("\(s.a.name) and \(s.b.name)")
                Text(s.reason).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Merge") { kb.merge(s) }
                    Button("Not the Same") { kb.reject(s) }
                    Spacer()
                    if kb.suggestions.count > 1 { Text("\(kb.suggestions.count - 1) more").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.14)))
            .padding([.horizontal, .top], 8)
        }
        if kb.lastMerge != nil {
            HStack {
                Text("Merged.").foregroundStyle(.secondary)
                Button("Undo") { kb.undoLastMerge() }.buttonStyle(.link)
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.top, 4)
        }
    }
}

private struct EntityCardView: View {
    let id: Int64
    let open: (Int64) -> Void
    @State private var detail: EntityDetail?
    @State private var role = ""
    @State private var org = ""
    @State private var notes = ""
    @State private var confirmForget = false
    @State private var todos = TodoCenter.shared

    var body: some View {
        ScrollView {
            if let d = detail {
                VStack(alignment: .leading, spacing: 16) {
                    header(d)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Role").foregroundStyle(.secondary)
                            TextField("Not known yet", text: $role).textFieldStyle(.roundedBorder).onSubmit(save)
                        }
                        GridRow {
                            Text("Organisation").foregroundStyle(.secondary)
                            TextField("Not known yet", text: $org).textFieldStyle(.roundedBorder).onSubmit(save)
                        }
                    }
                    if let last = d.recent.first {
                        Label("Last seen in \(last.app)\(last.chat.map { " · \($0)" } ?? "") \(last.ts.formatted(.relative(presentation: .named)))",
                              systemImage: "clock").foregroundStyle(.secondary)
                    }
                    if !d.identifiers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(d.identifiers.enumerated()), id: \.offset) { _, ident in
                                Label(ident.value, systemImage: ident.type == "email" ? "envelope" : ident.type == "phone" ? "phone" : "at")
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    let theirTodos = todos.open.filter { t in
                        t.people.contains { EntityRules.normalize($0) == EntityRules.normalize(d.summary.name) || d.aliases.contains($0) }
                    }
                    if !theirTodos.isEmpty {
                        section("Open to-dos") { ForEach(theirTodos) { TodoRow(todo: $0) } }
                    }
                    if !d.related.isEmpty {
                        section("Connected") {
                            RelatedGraph(center: d.summary.name, related: d.related.map { ($0.entity.name, $0.kind) })
                                .frame(height: 170)
                            FlowChips(items: d.related.map { ($0.entity.id, $0.entity.name) }, action: open)
                        }
                    }
                    if !d.facts.isEmpty {
                        section("What Gobbl picked up") {
                            ForEach(Array(d.facts.enumerated()), id: \.offset) { _, fact in
                                Text("\(fact.key.replacingOccurrences(of: "_", with: " ").capitalized): \(fact.value)")
                            }
                        }
                    }
                    section("Your notes") {
                        TextEditor(text: $notes).frame(minHeight: 60).font(.body)
                            .scrollContentBackground(.hidden).padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                    if !d.recent.isEmpty {
                        section("Recently") {
                            ForEach(d.recent, id: \.chunkID) { hit in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(MemoryRecall.source(hit)).font(.caption).foregroundStyle(.secondary)
                                    Text(hit.snippet).lineLimit(3).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { load() }
        .onDisappear(perform: save)
        .confirmationDialog("Forget \(detail?.summary.name ?? "this person")?", isPresented: $confirmForget) {
            Button("Forget and Never Remember", role: .destructive) { KnowledgeCenter.shared.forget(id) }
        } message: {
            Text("Everything Gobbl learned about them is deleted, and they won't be picked up again.")
        }
    }

    private func header(_ d: EntityDetail) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.summary.name).font(.title2.bold())
                if d.aliases.count > 1 {
                    Text("Also " + d.aliases.filter { $0 != d.summary.name }.prefix(4).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(d.summary.mentions30d) mentions in the last 30 days").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Menu {
                Button(d.summary.pinned ? "Unpin" : "Pin") { update(pinned: !d.summary.pinned) }
                Button("Hide") { update(hidden: true) }
                Divider()
                Button("Forget and Never Remember…", role: .destructive) { confirmForget = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func load() {
        guard let store = MemoryModel.shared.store, let d = (try? store.entityDetail(id)) ?? nil else { return }
        detail = d
        role = d.summary.role ?? ""
        org = d.summary.org ?? ""
        notes = d.notes
    }

    private func save() {
        guard let d = detail, let store = MemoryModel.shared.store else { return }
        try? store.updateEntity(id, role: role == (d.summary.role ?? "") ? nil : role,
                                org: org == (d.summary.org ?? "") ? nil : org, notes: notes == d.notes ? nil : notes)
    }

    private func update(pinned: Bool? = nil, hidden: Bool? = nil) {
        try? MemoryModel.shared.store?.updateEntity(id, pinned: pinned, hidden: hidden)
        KnowledgeCenter.shared.refresh()
        load()
    }
}

/// One person in the middle, their connections around them.
private struct RelatedGraph: View {
    let center: String
    let related: [(name: String, kind: String)]

    var body: some View {
        Canvas { c, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let items = Array(related.prefix(12))
            let radius = min(size.width, size.height) * 0.38
            for (i, item) in items.enumerated() {
                let angle = Double(i) / Double(max(1, items.count)) * 2 * .pi - .pi / 2
                let p = CGPoint(x: mid.x + CGFloat(cos(angle)) * radius * 1.4, y: mid.y + CGFloat(sin(angle)) * radius)
                var line = Path()
                line.move(to: mid)
                line.addLine(to: p)
                c.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                c.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(color(item.kind)))
                c.draw(Text(item.name).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: p.x, y: p.y + 11))
            }
            c.fill(Path(ellipseIn: CGRect(x: mid.x - 7, y: mid.y - 7, width: 14, height: 14)), with: .color(Palette.accent))
            c.draw(Text(center).font(.system(size: 11, weight: .semibold)), at: CGPoint(x: mid.x, y: mid.y + 16))
        }
    }

    private func color(_ kind: String) -> Color {
        switch kind {
        case "works_at": .orange
        case "member_of": .teal
        case "talks_with": .blue
        default: .purple
        }
    }
}

private struct FlowChips: View {
    let items: [(id: Int64, name: String)]
    let action: (Int64) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.id) { item in
                    Button(item.name) { action(item.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}

// MARK: Search

private struct SearchPane: View {
    @State private var query = ""
    @State private var hits: [MemoryStore.Hit] = []

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search everything Gobbl remembers", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            List(hits, id: \.chunkID) { hit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(MemoryRecall.source(hit)).font(.caption).foregroundStyle(.secondary)
                    Text(highlighted(hit.snippet)).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if hits.isEmpty && !query.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        }
        .onChange(of: query) { _, q in
            hits = (try? MemoryModel.shared.store?.search(q, limit: 80)) ?? []
        }
    }

    /// The FTS snippet marks matches with [ ]: show them bold instead.
    private func highlighted(_ snippet: String) -> AttributedString {
        var out = AttributedString()
        var bold = false
        var current = ""
        func flush() {
            var part = AttributedString(current)
            if bold { part.font = .body.bold() }
            out += part
            current = ""
        }
        for ch in snippet {
            if ch == "[" || ch == "]" {
                flush()
                bold = ch == "["
            } else {
                current.append(ch)
            }
        }
        flush()
        return out
    }
}
