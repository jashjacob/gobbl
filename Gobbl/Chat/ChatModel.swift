import AppKit
import GobblCore
import Observation

/// The Chat tab. Reminders are understood on the Mac and cost nothing;
/// everything else goes to Gobbl's AI with a small summary of your day
/// (calendar, reminders, agents, focus). The conversation is kept in memory
/// only and is gone when Gobbl quits.
@MainActor @Observable
final class ChatModel {
    static let shared = ChatModel()

    struct Message: Identifiable, Equatable {
        enum Kind: Equatable {
            case user
            case assistant
            case brief(BriefKind)
            case reminder(UUID)
            case note(symbol: String)
        }

        let id = UUID()
        var kind: Kind
        var text: String
        let date = Date()
    }

    private(set) var messages: [Message] = []
    private(set) var busy = false
    var draft = ""
    /// Something new arrived while the tab wasn't showing.
    var unread = false
    var visible = false

    static let starters = ["What's on today?", "Remind me in 20 minutes to stretch", "Brief me"]

    func send(_ text: String? = nil) {
        let text = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        draft = ""
        messages.append(Message(kind: .user, text: text))
        handle(text)
    }

    private func handle(_ text: String) {
        switch ReminderParser.parse(text, now: Date()) {
        case .reminder(let reminder)?:
            ReminderStore.shared.add(reminder)
            messages.append(Message(kind: .reminder(reminder.id), text: reminder.text))
            return
        case .needsTime(let task)?:
            reply("When should I remind you to \(task.prefix(1).lowercased() + task.dropFirst())? Try \"at 5pm\", \"in 20 minutes\" or \"tomorrow at 9\".")
            return
        case nil:
            break
        }
        let lower = text.lowercased()
        if ["brief me", "morning brief", "evening wrap", "wrap up my day"].contains(lower) {
            Routines.shared.runBrief(lower.contains("evening") || lower.contains("wrap") || Calendar.current.component(.hour, from: Date()) >= 14 ? .evening : .morning)
            return
        }
        guard AIClient.shared.isRegistered else {
            reply("Turn on AI in Settings to chat. Reminders already work: try \"remind me at 5 to stretch\".")
            return
        }

        let history: [[String: String]] = messages.suffix(13).compactMap { m in
            switch m.kind {
            case .user: ["role": "user", "content": String(m.text.prefix(4000))]
            case .assistant where !m.text.isEmpty: ["role": "assistant", "content": String(m.text.prefix(4000))]
            default: nil
            }
        }.suffix(12)
        // What memory knows about the people and things in the question.
        var chatContext = ChatContext.build()
        let recalled = MemoryRecall.items(for: text)
        if !recalled.isEmpty { chatContext["memory"] = recalled }
        let answer = Message(kind: .assistant, text: "")
        messages.append(answer)
        busy = true
        PetModel.shared.send(.assistantBusy(true))
        Task {
            defer {
                busy = false
                PetModel.shared.send(.assistantBusy(false))
            }
            do {
                for try await delta in AIClient.shared.stream("/v1/chat", body: ["messages": Array(history), "context": chatContext,
                                                                                  "locale": AIClient.locale]) {
                    update(answer.id) { $0.text += delta }
                }
            } catch {
                let message = (error as? AIClient.AIError)?.errorDescription ?? error.localizedDescription
                update(answer.id) { $0.text = $0.text.isEmpty ? message : $0.text + "\n\n" + message }
            }
            if !visible { unread = true }
        }
    }

    func reply(_ text: String) {
        messages.append(Message(kind: .assistant, text: text))
        if !visible { unread = true }
    }

    func addBrief(_ kind: BriefKind, _ text: String) {
        messages.append(Message(kind: .brief(kind), text: text))
        if !visible { unread = true }
    }

    /// A reminder going off, a nudge: a quiet line in the conversation.
    func note(_ text: String, symbol: String) {
        messages.append(Message(kind: .note(symbol: symbol), text: text))
        if !visible { unread = true }
    }

    func clear() { messages.removeAll() }

    private func update(_ id: UUID, _ change: (inout Message) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
    }
}

/// A short, structured summary of the user's day, sent with chat and briefs.
@MainActor
enum ChatContext {
    static func build() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        let calendar = CalendarModel.shared.events.prefix(8).map {
            ["title": String($0.title.prefix(80)), "start": iso.string(from: $0.start), "end": iso.string(from: $0.end)]
        }
        let reminders = ReminderStore.shared.open.prefix(10).map {
            ["text": String($0.text.prefix(120)), "due": iso.string(from: $0.due)]
        }
        let agents = AgentHub.shared.sessions.prefix(6).map { s -> [String: String] in
            let state: String = switch s.state {
            case .idle: "idle"
            case .working: "working"
            case .waiting(let why): "waiting for you: \(why)"
            case .done: "finished"
            }
            return ["project": s.project, "state": state]
        }
        return [
            "now": iso.string(from: Date()),
            "timezone": TimeZone.current.identifier,
            "calendar": calendar,
            "reminders": reminders,
            "agents": agents,
            "focus": ["running": FocusTimer.shared.isRunning, "completedToday": FocusTimer.shared.completedToday],
        ]
    }
}
