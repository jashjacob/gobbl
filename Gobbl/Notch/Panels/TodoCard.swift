import GobblCore
import SwiftUI

/// The top to-dos in the Home panel: what it is, why Gobbl thinks so, where
/// it came from, and Done / Dismiss. Hidden when there's nothing.
struct TodoCard: View {
    @State private var todos = TodoCenter.shared

    var body: some View {
        if let first = todos.autoDone.first, let resolved = first.resolvedAt, Date().timeIntervalSince(resolved) < 3600 {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                Text("Done: \(first.title)").font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Spacer(minLength: 4)
                Button("Undo") { todos.undo(first) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well))
        }
        if !todos.open.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("To do", systemImage: "checklist").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                    Spacer()
                    Button(todos.open.count > 2 ? "\(todos.open.count - 2) more" : "All") { MemoryWindow.show(.todos) }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                }
                ForEach(todos.open.prefix(2)) { todo in
                    TodoRow(todo: todo)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.well))
        }
    }
}

struct TodoRow: View {
    let todo: MemoryTodo
    @State private var todos = TodoCenter.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { todos.complete(todo) } label: {
                Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Done")
            VStack(alignment: .leading, spacing: 1) {
                Text(todo.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                if !todo.reason.isEmpty {
                    Text(todo.reason).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Text(source).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                if todo.status == .suggested { Button("Keep as a To-do") { todos.confirm(todo) } }
                Button("Snooze Until Tomorrow") { todos.snooze(todo, until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)).addingTimeInterval(9 * 3600)) }
                Divider()
                Button("Not a To-do") { todos.dismiss(todo) }
                Button("Already Done") { todos.dismiss(todo, reason: "already_done") }
                Button("Never Suggest from \(todo.sourceApp)") { todos.neverSuggest(from: todo.sourceApp) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var source: String {
        var parts = [todo.sourceApp]
        if let chat = todo.chat { parts.append(chat) } else if let domain = todo.domain { parts.append(domain) }
        if let due = todo.due { parts.append("due " + due.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}
