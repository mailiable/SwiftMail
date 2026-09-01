import Foundation
import Testing
@testable import SwiftMail

#if os(macOS)
    @Suite("Append Raw Message", .serialized, .timeLimit(.minutes(1)))
    struct AppendRawMessageTests {
        @Test("append preserves arbitrary RFC 822 bytes")
        func appendPreservesArbitraryBytes() async throws {
            var rawMessage = Data("From: sender@example.com\r\n\r\n".utf8)
            rawMessage.append(0xFF)

            let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let maildir = tempRoot.appendingPathComponent("Maildir")
            try FileManager.default.createDirectory(at: maildir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let testServer = try IMAPTestServer(maildirURL: maildir)
            try testServer.start()

            try await testServer.run {
                let server = IMAPServer(host: "127.0.0.1", port: testServer.port, useTLS: false)
                try await server.connect()
                try await server.login(username: testServer.username, password: testServer.password)

                try await server.append(
                    rawMessage: rawMessage,
                    to: "INBOX",
                    flags: [],
                    internalDate: nil
                )

                #expect(testServer.appendedMessages == [rawMessage])
                try await server.disconnect()
            }
        }
    }
#endif
