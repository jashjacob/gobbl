import GobblCore
import SwiftUI

/// Chat in the notch: ask about your day, set reminders, read briefs.
struct ChatPanel: View {
    @State private var chat = ChatModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if chat.messages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    Text("Ask about your day, or set a reminder.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(ChatModel.starters, id: \.self) { starter in
                            Button(starter) { chat.send(starter) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 9)
                                .frame(height: 22)
                                .background(Capsule().fill(Palette.well))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(chat.messages) { MessageRow(message: $0).id($0.id) }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: chat.messages.last?.text) { _, _ in
                        if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                    .onAppear {
                        if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: chat.busy ? "ellipsis" : "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.pulse, isActive: chat.busy)
                    TextField("Ask Gobbl, or \"remind me at 5 to…\"", text: $chat.draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focused)
                        .onSubmit { chat.send() }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Palette.well))
                if !chat.messages.isEmpty {
                    IconButton(symbol: "trash", help: "Clear the conversation") { chat.clear() }
                }
            }
        }
        .onAppear {
            focused = true
            chat.visible = true
            chat.unread = false
            // Hold right ⌥ here to ask out loud.
            Dictation.shared.routeSpeech(to: "chat") { spoken in ChatModel.shared.send(spoken) }
        }
        .onDisappear {
            chat.visible = false
            Dictation.shared.stopRouting("chat")
        }
    }
}

private struct MessageRow: View {
    let message: ChatModel.Message
    @State private var store = ReminderStore.shared

    var body: some View {
        switch message.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.wellHover))
            }
        case .assistant:
            Text(LocalizedStringKey(message.text.isEmpty ? "…" : message.text))
                .font(.system(size: 12))
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .brief(let kind):
            ChatCard(symbol: kind == .morning ? "sun.horizon.fill" : "moon.stars.fill", title: kind.title) {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
            }
        case .reminder(let id):
            let reminder = store.reminders.first { $0.id == id }
            ChatCard(symbol: "bell.fill", title: reminder == nil ? "Reminder cancelled" : "Reminder set") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.text).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text)
                        if let reminder {
                            Text(reminder.done ? "Done" : ReminderStore.dueLabel(reminder))
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer()
                    if let reminder, !reminder.done {
                        Button("Cancel") { store.cancel(reminder.id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        case .note(let symbol):
            Label(message.text, systemImage: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

private struct ChatCard<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.accent)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.well))
    }
}
