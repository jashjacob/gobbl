import Foundation

public struct MCPToolResult: Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public enum MCPBridgeError: Error, Equatable {
    /// No one listening on the socket.
    case notRunning
    case noAnswer
}

/// The tools `gobbl-mcp` offers. Reads go straight to the memory database
/// (read-only); clipboard, reminders and to-do changes go to the running app
/// through `bridge`.
public final class MCPTools: @unchecked Sendable {
    /// Sends one request to the app and returns its answer.
    public typealias Bridge = ([String: Any]) throws -> [String: Any]

    private let openStore: () -> MemoryStore?
    private let bridge: Bridge?
    private let now: () -> Date
    private let calendar: Calendar

    public init(openStore: @escaping () -> MemoryStore?, bridge: Bridge?, now: @escaping () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.openStore = openStore
        self.bridge = bridge
        self.now = now
        self.calendar = calendar
    }

    // MARK: Definitions

    private static func tool(_ name: String, _ title: String, _ description: String, write: Bool = false,
                             properties: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        let annotations: [String: Any] = write
            ? ["title": title, "readOnlyHint": false, "destructiveHint": false, "openWorldHint": false]
            : ["title": title, "readOnlyHint": true, "openWorldHint": false]
        return ["name": name, "title": title, "description": description, "inputSchema": schema, "annotations": annotations]
    }

    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func integer(_ description: String, min: Int, max: Int, default value: Int? = nil) -> [String: Any] {
        var p: [String: Any] = ["type": "integer", "description": description, "minimum": min, "maximum": max]
        if let value { p["default"] = value }
        return p
    }

    private static let dateHelp = "A date (2026-09-14), a date-time (2026-09-14T15:00 or with a UTC offset), \"today\" or \"yesterday\"."
    static let todoStatuses = ["open", "done", "all", "suggested", "confirmed", "maybe", "snoozed", "dismissed"]

    /// In a fixed order, so clients can cache the list.
    public static var definitions: [[String: Any]] {
        [
            tool("search_memory", "Search memory",
                 "Search what the user saw or wrote on this Mac: chats (WhatsApp, Slack, Messages…), mail, web pages and documents Gobbl captured. Returns matching snippets with their source (app · chat or site · time), best and newest first. Every word must appear, so use a few distinctive words rather than a sentence.",
                 properties: [
                    "query": string("Words to look for, e.g. \"invoice march\"."),
                    "app": string("Only this app, e.g. \"WhatsApp\" or \"Slack\"."),
                    "person": string("Only messages from or chats with this person."),
                    "since": string("Only after this. " + dateHelp),
                    "until": string("Only before this. " + dateHelp),
                    "limit": integer("How many results (default 10).", min: 1, max: 50, default: 10),
                 ], required: ["query"]),
            tool("get_day", "Get a day",
                 "What the user did on one day: Gobbl's summary of the day if it has one, otherwise the apps and windows they used and for how long.",
                 properties: ["date": string(dateHelp)], required: ["date"]),
            tool("list_todos", "List to-dos",
                 "To-dos Gobbl noticed in the user's chats and pages, or that the user confirmed. Each has an id for mark_todo_done.",
                 properties: ["status": ["type": "string", "enum": todoStatuses, "default": "open",
                                         "description": "open (default): suggested, confirmed and snoozed. done: finished ones. all: everything."]]),
            tool("who_is", "Who is",
                 "Look up someone Gobbl knows by name: role, organisation, where they talk, related people and projects, and recent messages.",
                 properties: ["name": string("Their name or part of it, e.g. \"Samar\".")], required: ["name"]),
            tool("get_person", "Get person",
                 "The full card for a person (or project or organisation) by the id that who_is or get_project returned.",
                 properties: ["id": integer("The id.", min: 1, max: Int(Int32.max))], required: ["id"]),
            tool("get_project", "Get project",
                 "Look up a project by name: the people involved, facts Gobbl picked up, and recent mentions.",
                 properties: ["name": string("The project's name.")], required: ["name"]),
            tool("recent_activity", "Recent activity",
                 "Timeline of the windows the user had open in the last few hours, newest first, with a short excerpt of each.",
                 properties: ["hours": integer("How far back (default 3).", min: 1, max: 48, default: 3)]),
            tool("get_clipboard", "Get clipboard",
                 "The user's recent clipboard history from Gobbl, newest first: text, links and files (images as a placeholder).",
                 properties: ["limit": integer("How many items (default 10).", min: 1, max: 50, default: 10)]),
            tool("add_reminder", "Add reminder",
                 "Set a reminder in Gobbl on this Mac; Gob nudges the user at that time. Only when the user asks.", write: true,
                 properties: [
                    "text": string("What to remind them about. May include the time, e.g. \"call Sara at 3pm\"."),
                    "at": string("When, as a date-time like 2026-09-15T15:00. Leave out if the text says when."),
                 ], required: ["text"]),
            tool("mark_todo_done", "Mark to-do done",
                 "Tick off one of Gobbl's to-dos by its id from list_todos. Only when the user asks or says it's done.", write: true,
                 properties: ["id": integer("The to-do's id.", min: 1, max: Int(Int32.max))], required: ["id"]),
        ]
    }

    // MARK: Calling

    /// nil for an unknown tool (a protocol error); otherwise a result, failed or not.
    public func call(_ name: String, arguments: [String: Any]) -> MCPToolResult? {
        guard let definition = Self.definitions.first(where: { $0["name"] as? String == name }) else { return nil }
        if let problem = Self.validate(arguments, against: definition) { return MCPToolResult(problem, isError: true) }
        let args = Args(raw: arguments)
        do {
            var result = try run(name, args)
            result.text = MCPFormat.cap(result.text)
            return result
        } catch MCPBridgeError.notRunning {
            return MCPToolResult("Gobbl isn't running, so it can't do that right now. Open Gobbl and try again.", isError: true)
        } catch MCPBridgeError.noAnswer {
            return MCPToolResult("Gobbl didn't answer. Try again in a moment.", isError: true)
        } catch {
            return MCPToolResult("Gobbl couldn't read its memory: \(error)", isError: true)
        }
    }

    struct Args {
        let raw: [String: Any]

        func string(_ key: String) -> String? {
            guard let s = (raw[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }

        func int(_ key: String) -> Int? { Self.int(raw[key]) }

        static func int(_ value: Any?) -> Int? {
            if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                let d = n.doubleValue
                return d == d.rounded() && abs(d) < 1e15 ? Int(d) : nil
            }
            if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
    }

    static func validate(_ args: [String: Any], against definition: [String: Any]) -> String? {
        let schema = definition["inputSchema"] as? [String: Any] ?? [:]
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        for (key, value) in args.sorted(by: { $0.key < $1.key }) {
            guard let property = properties[key] else {
                return "Unknown argument \"\(key)\". This tool takes: \(properties.keys.sorted().joined(separator: ", "))."
            }
            switch property["type"] as? String {
            case "string":
                guard let s = value as? String else { return "\"\(key)\" must be a string." }
                if let allowed = property["enum"] as? [String], !allowed.contains(s) {
                    return "\"\(key)\" must be one of: \(allowed.joined(separator: ", "))."
                }
            case "integer":
                if Args.int(value) == nil { return "\"\(key)\" must be a whole number." }
            default:
                break
            }
        }
        for key in schema["required"] as? [String] ?? [] {
            let value = args[key]
            if value == nil || (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                return "Missing \"\(key)\"."
            }
        }
        return nil
    }

    private func run(_ name: String, _ args: Args) throws -> MCPToolResult {
        switch name {
        case "search_memory": return try withStore { try searchMemory($0, args) }
        case "get_day": return try withStore { try getDay($0, args) }
        case "list_todos": return try withStore { try listTodos($0, args) }
        case "who_is": return try withStore { try lookUp($0, name: args.string("name") ?? "", type: nil) }
        case "get_project": return try withStore { try lookUp($0, name: args.string("name") ?? "", type: .project) }
        case "get_person": return try withStore { try getPerson($0, args) }
        case "recent_activity": return try withStore { try recentActivity($0, args) }
        case "get_clipboard": return try getClipboard(args)
        case "add_reminder": return try addReminder(args)
        case "mark_todo_done": return try markTodoDone(args)
        default: return MCPToolResult("Unknown tool \(name).", isError: true)
        }
    }

    private func withStore(_ body: (MemoryStore) throws -> MCPToolResult) throws -> MCPToolResult {
        guard let store = openStore() else { return MCPToolResult(MCPFormat.memoryOff) }
        return try body(store)
    }

    private enum DateArg {
        case value(Date?)
        case bad(MCPToolResult)
    }

    private func date(_ args: Args, _ key: String, endOfDay: Bool) -> DateArg {
        guard let s = args.string(key) else { return .value(nil) }
        guard let d = MCPFormat.parseDate(s, endOfDay: endOfDay, now: now(), calendar: calendar) else {
            return .bad(MCPToolResult("Couldn't read \"\(s)\" as a date. \(Self.dateHelp)", isError: true))
        }
        return .value(d)
    }

    // MARK: Memory

    private func searchMemory(_ store: MemoryStore, _ args: Args) throws -> MCPToolResult {
        let query = args.string("query") ?? ""
        let since: Date?, until: Date?
        switch date(args, "since", endOfDay: false) {
        case .value(let d): since = d
        case .bad(let e): return e
        }
        switch date(args, "until", endOfDay: true) {
        case .value(let d): until = d
        case .bad(let e): return e
        }
        let limit = min(max(args.int("limit") ?? 10, 1), 50)
        let hits = try store.filteredSearch(query, app: args.string("app"), person: args.string("person"),
                                            since: since, until: until, limit: limit)
        var filters: [String] = []
        if let app = args.string("app") { filters.append("in \(app)") }
        if let person = args.string("person") { filters.append("with \(person)") }
        if let s = args.string("since") { filters.append("since \(s)") }
        if let u = args.string("until") { filters.append("until \(u)") }
        let scope = filters.isEmpty ? "" : " (" + filters.joined(separator: ", ") + ")"
        guard !hits.isEmpty else {
            return MCPToolResult("Nothing in Gobbl's memory matches \"\(query)\"\(scope). Try fewer or different words, or a wider date range.")
        }
        let title = "\(hits.count) \(hits.count == 1 ? "match" : "matches") for \"\(query)\"\(scope):"
        return MCPToolResult(MCPFormat.hits(hits, title: title, now: now(), calendar: calendar))
    }

    private func getDay(_ store: MemoryStore, _ args: Args) throws -> MCPToolResult {
        let s = args.string("date") ?? "today"
        guard let d = MCPFormat.parseDate(s, endOfDay: false, now: now(), calendar: calendar) else {
            return MCPToolResult("Couldn't read \"\(s)\" as a date. \(Self.dateHelp)", isError: true)
        }
        let start = calendar.startOfDay(for: d)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let title = MCPFormat.dayTitle(start, calendar: calendar)
        let digests = try store.digestParts(day: MCPFormat.dayKey(start, calendar: calendar))
        if !digests.isEmpty { return MCPToolResult(MCPFormat.digests(digests, title: title)) }
        let segments = try store.activity(from: start, to: min(end, now()))
        guard !segments.isEmpty else { return MCPToolResult("Gobbl has nothing from \(title).") }
        return MCPToolResult(MCPFormat.day(segments, title: title, calendar: calendar))
    }

    private func listTodos(_ store: MemoryStore, _ args: Args) throws -> MCPToolResult {
        let status = args.string("status") ?? "open"
        let statuses: [MemoryTodo.Status]
        switch status {
        case "open": statuses = [.confirmed, .suggested, .snoozed]
        case "done": statuses = [.done, .autoDone]
        case "all": statuses = MemoryTodo.Status.allCases
        default: statuses = MemoryTodo.Status(rawValue: status).map { [$0] } ?? []
        }
        var todos = try store.todos(statuses, limit: 100)
        if status == "open" { todos = TodoRules.sorted(todos) }
        guard !todos.isEmpty else { return MCPToolResult(status == "open" ? "No open to-dos." : "No \(status) to-dos.") }
        return MCPToolResult(MCPFormat.todos(todos, label: status, now: now(), calendar: calendar))
    }

    private func lookUp(_ store: MemoryStore, name: String, type: EntityType?) throws -> MCPToolResult {
        if let found = try store.findEntity(named: name, type: type), let detail = try store.entityDetail(found.id) {
            return MCPToolResult(MCPFormat.entity(detail, now: now(), calendar: calendar))
        }
        let kind = type == .project ? "project" : "anyone"
        let hits = try store.filteredSearch(name, limit: 5)
        guard !hits.isEmpty else { return MCPToolResult("Gobbl doesn't know \(kind) called \"\(name)\" yet.") }
        return MCPToolResult(MCPFormat.hits(hits, title: "Gobbl has no card for \"\(name)\" yet, but the name comes up here:",
                                            now: now(), calendar: calendar))
    }

    private func getPerson(_ store: MemoryStore, _ args: Args) throws -> MCPToolResult {
        let id = args.int("id") ?? 0
        guard let detail = try store.entityDetail(Int64(id)) else { return MCPToolResult("Nothing in Gobbl has the id \(id).", isError: true) }
        return MCPToolResult(MCPFormat.entity(detail, now: now(), calendar: calendar))
    }

    private func recentActivity(_ store: MemoryStore, _ args: Args) throws -> MCPToolResult {
        let hours = min(max(args.int("hours") ?? 3, 1), 48)
        let segments = try store.activity(from: now().addingTimeInterval(-Double(hours) * 3600), to: now())
        guard !segments.isEmpty else { return MCPToolResult("Gobbl captured nothing in the last \(hours) h.") }
        return MCPToolResult(MCPFormat.timeline(segments, hours: hours, now: now(), calendar: calendar))
    }

    // MARK: Through the app

    private func ask(_ request: [String: Any]) throws -> [String: Any] {
        guard let bridge else { throw MCPBridgeError.notRunning }
        return try bridge(request)
    }

    private func getClipboard(_ args: Args) throws -> MCPToolResult {
        let limit = min(max(args.int("limit") ?? 10, 1), 50)
        let reply = try ask(["tool": "get_clipboard", "limit": limit])
        if let error = reply["error"] as? String { return MCPToolResult(error, isError: true) }
        if reply["off"] as? Bool == true { return MCPToolResult("Clipboard history is turned off in Gobbl.") }
        let items = reply["items"] as? [[String: Any]] ?? []
        guard !items.isEmpty else { return MCPToolResult("The clipboard history is empty.") }
        return MCPToolResult(MCPFormat.clipboard(items, now: now(), calendar: calendar))
    }

    private func addReminder(_ args: Args) throws -> MCPToolResult {
        let text = args.string("text") ?? ""
        let reminder: Reminder
        if let at = args.string("at") {
            guard var due = MCPFormat.parseDate(at, endOfDay: false, now: now(), calendar: calendar) else {
                return MCPToolResult("Couldn't read \"\(at)\" as a time. Use a date-time like 2026-09-15T15:00.", isError: true)
            }
            // A bare date means that morning.
            if at.count == 10 { due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due }
            guard due > now().addingTimeInterval(-60) else { return MCPToolResult("That time has already passed.", isError: true) }
            reminder = Reminder(text: text, due: due)
        } else {
            let phrase = text.lowercased().hasPrefix("remind") ? text : "remind me to " + text
            guard case .reminder(let r)? = ReminderParser.parse(phrase, now: now(), calendar: calendar) else {
                return MCPToolResult("When should Gobbl remind them? Pass \"at\" as a date-time like 2026-09-15T15:00, or put the time in the text (\"call Sara at 3pm\").",
                                     isError: true)
            }
            reminder = r
        }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reminder))
        let reply = try ask(["tool": "add_reminder", "reminder": encoded])
        if let error = reply["error"] as? String { return MCPToolResult(error, isError: true) }
        let when = MCPFormat.time(reminder.due, now: now(), calendar: calendar)
        let repeats = reminder.repeats.map { " (\($0.label.lowercased()))" } ?? ""
        return MCPToolResult("Reminder set for \(when)\(repeats): \(reminder.text)")
    }

    private func markTodoDone(_ args: Args) throws -> MCPToolResult {
        let id = args.int("id") ?? 0
        let reply = try ask(["tool": "mark_todo_done", "id": id])
        if let error = reply["error"] as? String { return MCPToolResult(error, isError: true) }
        return MCPToolResult("Marked done: \(reply["title"] as? String ?? "to-do #\(id)")")
    }
}
