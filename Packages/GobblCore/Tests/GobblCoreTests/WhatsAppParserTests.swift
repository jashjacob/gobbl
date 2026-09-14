import Testing
@testable import GobblCore

/// Made-up messages in the shape WhatsApp for Mac exposes through Accessibility.
@Suite struct WhatsAppParserTests {
    private let lrm = "\u{200E}"

    @Test func messagesSendersAndMe() {
        let nodes = [
            AXNode(role: "AXHeading", text: "\(lrm)Chats"),
            AXNode(role: "AXStaticText", text: "\(lrm)Mom sent a photo 😮 in \"Family\"", x: 0.04, width: 0.21), // chat list preview
            AXNode(role: "AXStaticText", text: "\(lrm)Message from Samar Mustafa, can you send the Q3 deck by Friday?, 6:02 PM", x: 0.27, width: 0.43),
            AXNode(role: "AXStaticText", text: "\(lrm)Message from Kevin John, Sure, I'll share it tomorrow, 6:05 PM, Read", x: 0.27, width: 0.3),
            AXNode(role: "AXStaticText", text: "\(lrm)Photo from Samar Mustafa, the slide, 6:07 PM", x: 0.27, width: 0.2),
        ]
        let messages = MessagingParser.parse(bundleID: "net.whatsapp.WhatsApp", nodes: nodes, me: ["Kevin John"])
        #expect(messages == [
            ChatMessage(sender: "Samar Mustafa", text: "can you send the Q3 deck by Friday?", fromMe: false),
            ChatMessage(sender: nil, text: "Sure, I'll share it tomorrow", fromMe: true),
            ChatMessage(sender: "Samar Mustafa", text: "the slide", fromMe: false),
        ])
        #expect(MessagingParser.chatFromSenders(messages) == "Samar Mustafa")
    }

    @Test func groupChatsHaveNoSingleOtherPerson() {
        let messages = [
            ChatMessage(sender: "Anita", text: "hi", fromMe: false),
            ChatMessage(sender: "Pritesh", text: "hello", fromMe: false),
        ]
        #expect(MessagingParser.chatFromSenders(messages) == nil)
    }

    @Test func otherAppsUseTheSharedReader() {
        let nodes = [AXNode(role: "AXStaticText", text: "Message from Samar, hi, 6:02 PM")]
        #expect(MessagingParser.parse(bundleID: "com.tinyspeck.slackmacgap", nodes: nodes, me: []).first?.sender == nil)
    }

    @Test func invisibleMarksAreStripped() {
        #expect("\u{200E}WhatsApp".strippingBidiMarks == "WhatsApp")
        #expect(GenericParser.lines([AXNode(role: "AXStaticText", text: "\u{200E}Chats")]) == ["Chats"])
    }
}
