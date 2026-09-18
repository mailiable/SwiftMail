import CustomDump
import NIO
import Testing
@testable import SwiftMail

@Suite(.timeLimit(.minutes(1)))
struct NamedGmailCommandsTests {
    // Detects trigger removal replacing the complete Gmail label set.
    @Test
    func namedConnectionRemovesOnlyTheSuppliedGmailLabel() async throws {
        let commands = try await GmailConnectionCommands()
        let result = Task {
            try await commands.named.removeGmailLabels(
                ["Cloak-Uncloak"],
                from: UIDSet([UID(42)])
            )
        }
        let command = try await commands.nextCommand()
        expectNoDifference(
            command,
            "A001 UID STORE 42 -X-GM-LABELS.SILENT (\"Cloak-Uncloak\")\r\n"
        )
        try await commands.respond("A001 OK stored\r\n")
        try await result.value
        try await commands.finish()
    }

    // Detects empty replacement labels being ignored instead of clearing the labels.
    @Test
    func primaryConnectionClearsGmailLabels() async throws {
        let commands = try await GmailConnectionCommands()
        let result = Task { try await commands.server.setGmailLabels([], on: UIDSet([UID(42)])) }
        let command = try await commands.nextCommand()
        expectNoDifference(command, "A001 UID STORE 42 X-GM-LABELS.SILENT ()\r\n")
        try await commands.respond("A001 OK stored\r\n")
        try await result.value
        try await commands.finish()
    }

    // System labels are emitted as atoms; malformed input must never become command text.
    @Test
    func namedConnectionRejectsMalformedSystemLabel() async throws {
        let commands = try await GmailConnectionCommands()
        await #expect {
            try await commands.named.setGmailLabels(["\\Inbox)\r\nA002 EXPUNGE"], on: UIDSet([UID(42)]))
        } throws: { error in
            if case IMAPError.invalidArgument = error { return true }
            return false
        }
        let outbound = try await commands.channel.readOutbound(as: ByteBuffer.self)
        expectNoDifference(outbound, nil)
        try await commands.finish()
    }

    // Detects named connections losing returned UID identity or decoded label names.
    @Test
    func `Named connection reads Gmail identity and labels`() async throws {
        let commands = try await GmailConnectionCommands()
        let result = Task { try await commands.named.fetchGmailAttributes(for: UIDSet([UID(42)])) }
        let command = try await commands.nextCommand()
        expectNoDifference(command, "A001 UID FETCH 42 (UID X-GM-MSGID X-GM-THRID X-GM-LABELS)\r\n")
        try await commands.respond("* 1 FETCH (UID 42 X-GM-MSGID 123 X-GM-THRID 456 X-GM-LABELS (\\Inbox \"Work\"))\r\nA001 OK fetched\r\n")
        let attributes = try await result.value
        expectNoDifference(attributes, [UID(42): GmailMessageAttributes(messageID: 123, threadID: 456, labels: ["\\Inbox", "Work"])])
        try await commands.finish()
    }

    // Detects loss of system labels, escaping, hierarchy, or non-ASCII names on replacement.
    @Test
    func `Named connection replaces labels without changing their names`() async throws {
        let commands = try await GmailConnectionCommands()
        let result = Task { try await commands.named.setGmailLabels(["\\Inbox", "Work/Travel", "Café", "A&B", "Say \"hi\""], on: UIDSet([UID(42)])) }
        let command = try await commands.nextCommand()
        expectNoDifference(command, "A001 UID STORE 42 X-GM-LABELS.SILENT (\\Inbox \"Work/Travel\" \"Caf&AOk-\" \"A&-B\" \"Say \\\"hi\\\"\")\r\n")
        try await commands.respond("A001 OK stored\r\n")
        try await result.value
        try await commands.finish()
    }

    // Detects a known unsupported command being sent to a non-Gmail server.
    @Test
    func `Named connection rejects label writes when Gmail is not advertised`() async throws {
        let commands = try await GmailConnectionCommands(supportsGmail: false)
        await #expect {
            try await commands.named.setGmailLabels(["Work"], on: UIDSet([UID(42)]))
        } throws: { error in
            if case IMAPError.commandNotSupported("X-GM-EXT-1") = error { return true }
            return false
        }
        let outbound = try await commands.channel.readOutbound(as: ByteBuffer.self)
        expectNoDifference(outbound, nil)
        try await commands.finish()
    }

    // Detects a read being issued before Gmail support is established.
    @Test
    func `Named connection rejects Gmail reads when Gmail is not advertised`() async throws {
        let commands = try await GmailConnectionCommands(supportsGmail: false)
        await #expect {
            try await commands.named.fetchGmailAttributes(for: UIDSet([UID(42)]))
        } throws: { error in
            if case IMAPError.commandNotSupported("X-GM-EXT-1") = error { return true }
            return false
        }
        let outbound = try await commands.channel.readOutbound(as: ByteBuffer.self)
        expectNoDifference(outbound, nil)
        try await commands.finish()
    }

    // Detects a rejected STORE being reported as a successful label replacement.
    @Test
    func `Named connection reports a rejected label replacement`() async throws {
        let commands = try await GmailConnectionCommands()
        let result = Task { try await commands.named.setGmailLabels(["Work"], on: UIDSet([UID(42)])) }
        _ = try await commands.nextCommand()
        try await commands.respond("A001 NO label write refused\r\n")
        await #expect(throws: (any Error).self) { try await result.value }
        try await commands.finish()
    }
}
