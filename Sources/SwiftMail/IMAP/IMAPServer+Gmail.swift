import Foundation
import NIOIMAPCore

extension IMAPServer {
    /// Whether the authenticated connection advertised Gmail's IMAP extensions.
    public var supportsGmailExtensions: Bool {
        capabilities.contains(.gmailExtensions)
    }

    /// Fetches Gmail-native attributes for the given UIDs.
    ///
    /// Requires `X-GM-EXT-1`; unsupported connections reject the call locally.
    public func fetchGmailAttributes(
        for identifierSet: UIDSet
    ) async throws -> [UID: GmailMessageAttributes] {
        try await ensurePrimaryConnectionAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        let command = FetchGmailAttributesCommand(identifierSet: identifierSet)
        let records = try await executeCommand(command)

        return gmailAttributesByUID(records)
    }

    /// Replaces the message's Gmail labels, preserving the supplied Unicode names.
    /// Requires an authenticated connection advertising `X-GM-EXT-1`.
    public func setGmailLabels(_ labels: [String], on identifiers: UIDSet) async throws {
        let command = try StoreCommand(identifierSet: identifiers, gmailLabels: labels)
        try command.validate()
        try await ensurePrimaryConnectionAuthenticated()
        guard supportsGmailExtensions else {
            throw IMAPError.commandNotSupported("X-GM-EXT-1")
        }
        try await executeCommand(command)
    }
}

func gmailAttributesByUID(_ records: [GmailAttributeRecord]) -> [UID: GmailMessageAttributes] {
    var result: [UID: GmailMessageAttributes] = [:]
    for record in records {
        guard let uid = record.uid,
              let messageID = record.messageID,
              let threadID = record.threadID
        else { continue }
        result[uid] = GmailMessageAttributes(messageID: messageID, threadID: threadID, labels: record.labels)
    }
    return result
}
