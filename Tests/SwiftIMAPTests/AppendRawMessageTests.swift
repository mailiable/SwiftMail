import Foundation
import Testing
@testable import SwiftMail

#if os(macOS)
    @Suite("Append Raw Message", .serialized, .timeLimit(.minutes(1)))
    struct AppendRawMessageTests {
        @Test("append preserves arbitrary RFC 822 bytes on primary and independent named connections", arguments: [false, true])
        func appendPreservesArbitraryBytes(namedConnection: Bool) async throws {
            // Regression: a named APPEND must preserve raw bytes and finish while the primary queue is held.
            var rawMessage = Data("From: sender@example.com\r\n\r\n".utf8)
            rawMessage.append(0xFF)

            let tempRoot = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask,
                appropriateFor: FileManager.default.temporaryDirectory, create: true)
            let maildir = tempRoot.appendingPathComponent("Maildir")
            try FileManager.default.createDirectory(at: maildir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let testServer = try IMAPTestServer(maildirURL: maildir)
            try testServer.start()

            try await testServer.run {
                let server = IMAPServer(host: "127.0.0.1", port: testServer.port, useTLS: false)
                try await server.connect()
                try await server.login(username: testServer.username, password: testServer.password)

                if namedConnection {
                    let mailbox = try await server.connection(named: "mutation")
                    try await mailbox.connect()
                    let heldPrimary = HeldIMAPCommandQueue(await server.primaryConnection.commandQueue)
                    await heldPrimary.waitUntilHeld()
                    defer { heldPrimary.release() }
                    try await mailbox.append(rawMessage: rawMessage, to: "INBOX", flags: [], internalDate: nil)
                    #expect(testServer.appendedMessages == [rawMessage])
                    heldPrimary.release()
                    await heldPrimary.finish()
                    try await mailbox.disconnect()
                } else {
                    try await server.append(rawMessage: rawMessage, to: "INBOX", flags: [], internalDate: nil)
                }

                #expect(testServer.appendedMessages == [rawMessage])
                try await server.disconnect()
            }
        }
    }
#endif
