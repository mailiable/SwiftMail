import Foundation
import NIOIMAPCore

extension IMAPNamedConnection {
    /// Whether the authenticated connection advertised Gmail's IMAP extensions.
    public var supportsGmailExtensions: Bool {
        capabilities.contains(.gmailExtensions)
    }

    /// Reads Gmail identities and labels in this connection's selected mailbox.
    public func fetchGmailAttributes(for identifiers: UIDSet) async throws -> [UID: GmailMessageAttributes] {
        try await ensureAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        let records = try await executeCommand(FetchGmailAttributesCommand(identifierSet: identifiers))
        return gmailAttributesByUID(records)
    }

    /// Replaces the message's Gmail labels, preserving the supplied Unicode names.
    /// Requires an authenticated connection advertising `X-GM-EXT-1`.
    public func setGmailLabels(_ labels: [String], on identifiers: UIDSet) async throws {
        let command = try StoreCommand(identifierSet: identifiers, gmailLabels: labels)
        try command.validate()
        try await ensureAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        try await executeCommand(command)
    }
}
