import AppKit
import GobblCore

/// The app's end of gobbl-mcp's requests: clipboard, reminders and to-dos
/// live in the running app, so those tools come here over the agent socket
/// as `mcp\t{json}` and get one JSON line back.
@MainActor
enum MCPBridge {
    static func handle(_ json: String, reply: AgentReply) {
        let answer = respond(to: Data(json.utf8))
        let data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(#"{"error":"Gobbl couldn't answer."}"#.utf8)
        reply.send(String(decoding: data, as: UTF8.self))
    }

    static func respond(to data: Data) -> [String: Any] {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tool = request["tool"] as? String else {
            return ["error": "Gobbl didn't understand that request."]
        }
        switch tool {
        case "get_clipboard": return clipboard(limit: request["limit"] as? Int ?? 10)
        case "add_reminder": return addReminder(request["reminder"])
        case "mark_todo_done": return markDone((request["id"] as? NSNumber)?.int64Value ?? 0)
        default: return ["error": "Gobbl doesn't know \(tool)."]
        }
    }

    private static func clipboard(limit: Int) -> [String: Any] {
        let model = ClipboardModel.shared
        guard model.enabled else { return ["off": true] }
        let items = model.history.items.prefix(min(max(limit, 1), 50)).map { item -> [String: Any] in
            var entry: [String: Any] = ["kind": item.kind.rawValue, "date": item.date.timeIntervalSince1970, "pinned": item.pinned]
            // Images are stored as a file name; that means nothing to an AI app.
            entry["text"] = item.kind == .image ? "" : String(item.text.prefix(2000))
            if let app = item.sourceApp { entry["app"] = app }
            return entry
        }
        return ["items": items]
    }

    private static func addReminder(_ value: Any?) -> [String: Any] {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value),
              var reminder = try? JSONDecoder().decode(Reminder.self, from: data) else {
            return ["error": "That reminder didn't make sense to Gobbl."]
        }
        reminder.id = UUID()
        reminder.done = false
        ReminderStore.shared.add(reminder)
        return ["ok": true]
    }

    private static func markDone(_ id: Int64) -> [String: Any] {
        guard let store = MemoryModel.shared.store else { return ["error": "Gobbl's Memory is off, so there are no to-dos."] }
        guard let todo = (try? store.todos(MemoryTodo.Status.allCases, limit: 5000))?.first(where: { $0.id == id }) else {
            return ["error": "There's no to-do #\(id). list_todos shows the ids."]
        }
        guard todo.status.isOpen else { return ["title": todo.title, "note": "It was already \(todo.status.rawValue)."] }
        TodoCenter.shared.complete(todo)
        TodoCenter.shared.reload()
        return ["title": todo.title]
    }
}
