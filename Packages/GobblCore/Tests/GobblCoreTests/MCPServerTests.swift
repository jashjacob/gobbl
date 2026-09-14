import Foundation
import Testing
@testable import GobblCore

@Suite struct MCPServerTests {
    private func server(store: MemoryStore? = nil, bridge: MCPTools.Bridge? = nil, log: ((String) -> Void)? = nil) -> MCPServer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return MCPServer(version: "1.2.3", tools: MCPTools(openStore: { store }, bridge: bridge, calendar: calendar), onToolCall: log)
    }

    private func send(_ s: MCPServer, _ json: String) -> [String: Any]? {
        guard let line = s.handle(line: json) else { return nil }
        #expect(!line.contains("\n"))
        return try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private func call(_ s: MCPServer, _ tool: String, _ args: String = "{}") -> (text: String, isError: Bool) {
        let reply = send(s, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(args)}}"#)
        let result = reply?["result"] as? [String: Any]
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (text, result?["isError"] as? Bool ?? false)
    }

    private func errorCode(_ reply: [String: Any]?) -> Int? { (reply?["error"] as? [String: Any])?["code"] as? Int }

    // MARK: Protocol

    @Test func initializeEchoesKnownVersions() {
        for version in ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"] {
            let reply = send(server(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
            let result = reply?["result"] as? [String: Any]
            #expect(result?["protocolVersion"] as? String == version)
            #expect((result?["serverInfo"] as? [String: Any])?["name"] as? String == "gobbl")
            #expect((result?["serverInfo"] as? [String: Any])?["version"] as? String == "1.2.3")
            #expect((result?["capabilities"] as? [String: Any])?["tools"] != nil)
            #expect((result?["instructions"] as? String)?.isEmpty == false)
            #expect(reply?["id"] as? Int == 1)
        }
    }

    @Test func initializeAnswersNewestForUnknownVersions() {
        let reply = send(server(), #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        #expect((reply?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-11-25")
        #expect(reply?["id"] as? String == "a")
    }

    @Test func notificationsGetNoReply() {
        #expect(server().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(server().handle(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3}}"#) == nil)
        #expect(server().handle(line: "   ") == nil)
    }

    @Test func pingAndErrors() {
        let s = server()
        #expect(send(s, #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"] != nil)
        #expect(errorCode(send(s, #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)) == -32601)
        #expect(errorCode(send(s, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rm_rf","arguments":{}}}"#)) == -32602)
        #expect(errorCode(send(s, "{not json")) == -32700)
        #expect(errorCode(send(s, #"{"jsonrpc":"1.0","id":5,"method":"ping"}"#)) == -32600)
    }

    @Test func toolsListDescribesEveryTool() throws {
        let reply = send(server(), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let tools = try #require((reply?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == [
            "search_memory", "get_day", "list_todos", "who_is", "get_person", "get_project", "recent_activity",
            "get_clipboard", "add_reminder", "mark_todo_done",
        ])
        for tool in tools {
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            #expect(schema["additionalProperties"] as? Bool == false)
            let annotations = try #require(tool["annotations"] as? [String: Any])
            let isWrite = ["add_reminder", "mark_todo_done"].contains(tool["name"] as? String)
            #expect(annotations["readOnlyHint"] as? Bool == !isWrite)
            if isWrite { #expect(annotations["destructiveHint"] as? Bool == false) } else { #expect(annotations["openWorldHint"] as? Bool == false) }
        }
        let search = try #require(tools.first)
        #expect(((search["inputSchema"] as? [String: Any])?["properties"] as? [String: [String: Any]])?["limit"]?["maximum"] as? Int == 50)
    }

    @Test func modernRevision() {
        let s = server()
        let discover = send(s, #"{"jsonrpc":"2.0","id":"d","method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#)
        let result = discover?["result"] as? [String: Any]
        #expect((result?["supportedVersions"] as? [String])?.contains("2026-07-28") == true)
        #expect(result?["resultType"] as? String == "complete")
        #expect(((result?["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"] as? [String: Any])?["name"] as? String == "gobbl")

        let list = send(s, #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#)
        #expect((list?["result"] as? [String: Any])?["resultType"] as? String == "complete")
        #expect((list?["result"] as? [String: Any])?["ttlMs"] != nil)

        let bad = send(s, #"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1900-01-01"}}}"#)
        #expect(errorCode(bad) == -32022)
        #expect(((bad?["error"] as? [String: Any])?["data"] as? [String: Any])?["requested"] as? String == "1900-01-01")
    }

    // MARK: Tools

    private func tempStore() throws -> (writer: MemoryStore, reader: MemoryStore) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-mcp-\(UUID().uuidString).sqlite")
        let writer = try MemoryStore(url: url)
        let t = Date().addingTimeInterval(-3600)
        let chat = try writer.beginSegment(appBundle: "net.whatsapp.WhatsApp", appName: "WhatsApp", window: "Samar", url: nil, chat: "Samar", at: t)
        try writer.addChunks(segment: chat, [
            .init(ts: t, kind: "message", sender: "Samar", text: "Can you send the invoice for March by Monday?"),
            .init(ts: t.addingTimeInterval(60), kind: "message", sender: "Me", fromMe: true, text: "Sure, sending the invoice tonight"),
        ])
        let slack = try writer.beginSegment(appBundle: "com.tinyspeck.slackmacgap", appName: "Slack", window: "#finance", url: nil,
                                            chat: "#finance", at: t.addingTimeInterval(600))
        try writer.addChunks(segment: slack, [.init(ts: t.addingTimeInterval(600), kind: "message", sender: "Ravi", text: "New invoice template is up")])
        return (writer, try MemoryStore(url: url, readOnly: true))
    }

    @Test func searchMemoryFindsAndFilters() throws {
        let (writer, reader) = try tempStore()
        var logged: [String] = []
        let s = server(store: reader, log: { logged.append($0) })

        let all = call(s, "search_memory", #"{"query":"invoice"}"#)
        #expect(!all.isError)
        #expect(all.text.contains("3 matches for \"invoice\""))
        #expect(all.text.contains("WhatsApp · Samar · Today"))
        #expect(all.text.contains("Slack · #finance"))
        #expect(all.text.contains("You: Sure, sending the [invoice] tonight"))

        let whatsapp = call(s, "search_memory", #"{"query":"invoice","app":"whatsapp","limit":1}"#)
        #expect(whatsapp.text.contains("1 match"))
        #expect(!whatsapp.text.contains("Slack"))

        let ravi = call(s, "search_memory", #"{"query":"invoice","person":"Ravi"}"#)
        #expect(ravi.text.contains("#finance") && !ravi.text.contains("WhatsApp"))

        let old = call(s, "search_memory", #"{"query":"invoice","until":"2020-01-01"}"#)
        #expect(old.text.hasPrefix("Nothing in Gobbl's memory matches"))
        #expect(logged == ["search_memory", "search_memory", "search_memory", "search_memory"])
        _ = writer
    }

    @Test func badArgumentsAreToolErrors() throws {
        let (_, reader) = try tempStore()
        let s = server(store: reader)
        #expect(call(s, "search_memory", #"{"query":"x","colour":"red"}"#).isError)
        #expect(call(s, "search_memory", #"{}"#).isError)
        #expect(call(s, "search_memory", #"{"query":"invoice","since":"last blue moon"}"#).isError)
        #expect(call(s, "recent_activity", #"{"hours":"lots"}"#).isError)
        #expect(call(s, "list_todos", #"{"status":"someday"}"#).isError)
    }

    @Test func otherReadTools() throws {
        let (writer, reader) = try tempStore()
        let s = server(store: reader)
        let recent = call(s, "recent_activity", #"{"hours":2}"#)
        #expect(recent.text.contains("Slack · #finance") && recent.text.contains("WhatsApp · Samar"))
        #expect(call(s, "get_day", #"{"date":"today"}"#).text.contains("## WhatsApp"))
        #expect(call(s, "who_is", #"{"name":"Ravi"}"#).text.contains("no card for \"Ravi\""))
        #expect(call(s, "list_todos").text == "No open to-dos.")
        _ = writer
    }

    @Test func memoryOffIsFriendly() {
        let r = call(server(), "search_memory", #"{"query":"invoice"}"#)
        #expect(!r.isError)
        #expect(r.text.contains("Turn on Memory in Gobbl"))
    }

    @Test func appToolsNeedGobblRunning() {
        #expect(call(server(), "get_clipboard").isError)
        let down = server(bridge: { _ in throw MCPBridgeError.notRunning })
        let r = call(down, "mark_todo_done", #"{"id":3}"#)
        #expect(r.isError && r.text.contains("Gobbl isn't running"))
    }

    @Test func appToolsGoThroughTheBridge() {
        var sent: [[String: Any]] = []
        let s = server(bridge: { request in
            sent.append(request)
            switch request["tool"] as? String {
            case "get_clipboard": return ["items": [["kind": "link", "text": "https://xeve.io", "date": Date().timeIntervalSince1970, "app": "Safari"]]]
            case "mark_todo_done": return ["title": "Send invoice"]
            default: return ["ok": true]
            }
        })
        #expect(call(s, "get_clipboard", #"{"limit":5}"#).text.contains("link · Safari"))
        #expect(call(s, "mark_todo_done", #"{"id":12}"#).text == "Marked done: Send invoice")
        let reminder = call(s, "add_reminder", #"{"text":"call Sara","at":"2099-01-02T15:00"}"#)
        #expect(!reminder.isError && reminder.text.hasSuffix(": call Sara"))
        #expect(call(s, "add_reminder", #"{"text":"call Sara"}"#).isError)
        #expect(sent.map { $0["tool"] as? String } == ["get_clipboard", "mark_todo_done", "add_reminder"])
        #expect(sent[0]["limit"] as? Int == 5)
        #expect((sent[2]["reminder"] as? [String: Any])?["text"] as? String == "call Sara")
    }

    @Test func longResultsAreCapped() {
        let long = (0..<2000).map { "line \($0)" }.joined(separator: "\n")
        let capped = MCPFormat.cap(long)
        #expect(capped.count < MCPFormat.maxChars + 200)
        #expect(capped.contains("more was cut"))
    }
}
