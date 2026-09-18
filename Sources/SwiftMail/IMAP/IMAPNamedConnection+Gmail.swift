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

    /// Finds this mailbox's UID for Gmail's stable, cross-mailbox message ID.
    public func searchGmailMessageID(_ messageID: UInt64) async throws -> UIDSet {
        try await ensureAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        return try await executeCommand(SearchGmailMessageIDCommand(messageID: messageID))
    }

    /// Adds Gmail labels without changing labels already applied to the message.
    public func addGmailLabels(_ labels: [String], to identifiers: UIDSet) async throws {
        let command = try StoreCommand(
            identifierSet: identifiers,
            gmailLabels: labels,
            operation: .add
        )
        try command.validate()
        try await ensureAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        try await executeCommand(command)
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

    /// Removes the supplied Gmail labels without changing any other labels.
    /// Requires an authenticated connection advertising `X-GM-EXT-1`.
    public func removeGmailLabels(_ labels: [String], from identifiers: UIDSet) async throws {
        let command = try StoreCommand(
            identifierSet: identifiers,
            gmailLabels: labels,
            operation: .remove
        )
        try command.validate()
        try await ensureAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        try await executeCommand(command)
    }
}
