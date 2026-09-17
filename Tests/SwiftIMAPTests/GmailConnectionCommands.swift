import NIO
import NIOEmbedded
import NIOIMAPCore
@testable import SwiftMail

/// Supplies wire responses to one connection and exposes the commands it sends.
final class GmailConnectionCommands {
    let server: SwiftMail.IMAPServer
    let named: IMAPNamedConnection
    let channel: NIOAsyncTestingChannel

    init(supportsGmail: Bool = true) async throws {
        server = SwiftMail.IMAPServer(host: "localhost", port: 143, useTLS: false)
        let connection = await server.primaryConnection
        channel = NIOAsyncTestingChannel()
        try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 143))
        try await channel.addIMAPClientHandler()
        try await channel.pipeline.addHandler(connection.duplexLogger)
        try await channel.pipeline.addHandler(connection.responseBuffer)
        connection.replaceChannelForTesting(channel)
        connection.replaceCapabilitiesForTesting(supportsGmail ? [.gmailExtensions] : [])
        named = IMAPNamedConnection(name: "gmail-test", connection: connection, authenticateOnConnection: { _ in })
    }

    func nextCommand() async throws -> String {
        let bytes = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
        return String(buffer: bytes)
    }

    func respond(_ response: String) async throws {
        try await channel.writeInbound(ByteBuffer(string: response))
    }

    func finish() async throws {
        _ = try await channel.finish()
    }
}
