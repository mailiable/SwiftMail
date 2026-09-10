#if os(macOS)
import Foundation
import Testing
@testable import SwiftMail

/// Uses the real socket, authentication, command queue and mailbox commands.
private final class SessionReadinessServer {
    let peer: IMAPTestServer
    let client: IMAPServer
    let maildir: URL

    init() throws {
        maildir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory, create: true)
        try FileManager.default.createDirectory(
            at: maildir.appendingPathComponent("cur"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: maildir.appendingPathComponent("new"), withIntermediateDirectories: true)
        peer = try IMAPTestServer(advertisedCapabilities: ["IMAP4rev1", "UIDPLUS"], maildirURL: maildir)
        try peer.start()
        client = IMAPServer(host: "127.0.0.1", port: peer.port, useTLS: false)
    }

    func run(_ test: (SessionReadinessServer) async throws -> Void) async throws {
        do {
            try await client.connect()
            try await client.login(username: "testuser", password: "testpass")
            try await test(self)
            try await client.disconnect()
            await peer.stop()
            try FileManager.default.removeItem(at: maildir)
        } catch {
            try? await client.disconnect()
            await peer.stop()
            try? FileManager.default.removeItem(at: maildir)
            throw error
        }
    }

    var commands: [String] {
        peer.commandLog.map { String($0.split(separator: " ", maxSplits: 1)[1]) }
    }

    func dropTransport(_ connection: IMAPConnection) async throws {
        try await connection.commandQueue.run {
            try await connection.channel?.close().get()
        }
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct IMAPSessionReadinessTests {
    @Test(arguments: [false, true], [false, true])
    func commandsWaitForAuthenticationAndMailboxAfterTransportCloses(named: Bool, readOnly: Bool) async throws {
        // Regression: a stale authenticated flag lets NOOP reconnect, then SEARCH
        // reaches the new socket before authentication and SELECT have completed.
        try await SessionReadinessServer().run { harness in
            let handle = named ? try await harness.client.connection(named: "source") : nil
            let connection: IMAPConnection
            if let handle { connection = await handle.connection }
            else { connection = await harness.client.primaryConnection }
            if let handle {
                if readOnly { _ = try await handle.examineMailbox("Banana") }
                else { _ = try await handle.select(mailbox: "Banana") }
            } else {
                if readOnly { _ = try await harness.client.examineMailbox("Banana") }
                else { _ = try await harness.client.selectMailbox("Banana") }
            }
            let before = harness.commands.count
            try await harness.dropTransport(connection)
            if let handle {
                async let noop = handle.noop()
                async let search: ExtendedSearchResult<UID> = handle.extendedSearch(criteria: [.all])
                let (_, result) = try await (noop, search)
                #expect((result.all?.toArray() ?? result.ordered ?? []) == [])
            } else {
                async let noop = harness.client.noop()
                async let search: ExtendedSearchResult<UID> = harness.client.extendedSearch(criteria: [.all])
                let (_, result) = try await (noop, search)
                #expect((result.all?.toArray() ?? result.ordered ?? []) == [])
            }
            let sent = Array(harness.commands.dropFirst(before))
            #expect(Array(sent.prefix(4)) == [
                "CAPABILITY", "LOGIN \"testuser\" \"testpass\"", "CAPABILITY",
                "\(readOnly ? "EXAMINE" : "SELECT") \"Banana\""
            ])
            #expect(sent.count == 6)
            #expect(sent.dropFirst(4).contains("NOOP"))
            #expect(sent.dropFirst(4).contains { $0.hasPrefix("UID SEARCH ") })
        }
    }

    @Test
    func failedMailboxRestorationPreventsSearchFromBeingSent() async throws {
        // Regression: successful authentication alone is treated as a ready mailbox.
        try await SessionReadinessServer().run { harness in
            let handle = try await harness.client.connection(named: "sink")
            try await handle.select(mailbox: "BananaCloaked")
            let connection = await handle.connection
            try await harness.dropTransport(connection)
            let before = harness.commands.count
            harness.peer.enqueueResponse("$TAG NO Mailbox unavailable\r\n", for: "SELECT")
            do {
                let _: ExtendedSearchResult<UID> = try await handle.extendedSearch(criteria: [.all])
                Issue.record("Search should fail while mailbox selection is unavailable")
            } catch {
                #expect(String(describing: error).contains("Mailbox unavailable"))
            }
            #expect(Array(harness.commands.dropFirst(before)) == [
                "CAPABILITY", "LOGIN \"testuser\" \"testpass\"", "CAPABILITY", "SELECT \"BananaCloaked\""
            ])
            // A later request can proceed once selection succeeds, without another login.
            let result: ExtendedSearchResult<UID> = try await handle.extendedSearch(criteria: [.all])
            #expect((result.all?.toArray() ?? result.ordered ?? []) == [])
            #expect(harness.commands.suffix(2).first == "SELECT \"BananaCloaked\"")
        }
    }

    @Test
    func changedUIDValidityPreventsCommandsUntilCallerSelectsMailboxAgain() async throws {
        // Regression: restoring a replaced mailbox silently reuses obsolete message UIDs.
        try await SessionReadinessServer().run { harness in
            let handle = try await harness.client.connection(named: "source")
            try await handle.select(mailbox: "Banana")
            try await harness.dropTransport(await handle.connection)
            let before = harness.commands.count
            harness.peer.enqueueResponse(
                "* 0 EXISTS\r\n* OK [UIDVALIDITY 2] changed\r\n$TAG OK selected\r\n", for: "SELECT")
            do {
                let _: ExtendedSearchResult<UID> = try await handle.extendedSearch(criteria: [.all])
                Issue.record("Search should reject changed UID validity")
            } catch {
                #expect(String(describing: error).contains("UID validity changed"))
            }
            #expect(!harness.commands.dropFirst(before).contains { $0.hasPrefix("UID SEARCH") })
            // An explicit selection establishes the caller's new mailbox context.
            try await handle.select(mailbox: "Banana")
            let result: ExtendedSearchResult<UID> = try await handle.extendedSearch(criteria: [.all])
            #expect((result.all?.toArray() ?? result.ordered ?? []) == [])
        }
    }
}
#endif
