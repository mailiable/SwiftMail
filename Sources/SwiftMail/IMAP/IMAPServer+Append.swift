import Foundation
@preconcurrency import NIOIMAP
import NIOIMAPCore

// MARK: - Append Commands

extension IMAPServer {
    /// Append a raw RFC 822 message to a mailbox.
    ///
    /// - Parameters:
    ///   - rawMessage: The complete RFC 822 message as a string.
    ///   - mailbox: The destination mailbox path (e.g. "Sent").
    ///   - flags: Flags to set on the appended message.
    ///   - internalDate: Optional internal date to store on the server.
    /// - Returns: ``AppendResult`` describing server-assigned identifiers.
    @discardableResult
    public func append(
        rawMessage: String,
        to mailbox: String,
        flags: [Flag],
        internalDate: Date?
    ) async throws -> AppendResult {
        try await append(
            rawMessage: Data(rawMessage.utf8),
            to: mailbox,
            flags: flags,
            internalDate: internalDate
        )
    }

    /// Append raw RFC 822 message bytes to a mailbox.
    ///
    /// This overload preserves arbitrary message bytes, including content that is not valid UTF-8.
    ///
    /// - Parameters:
    ///   - rawMessage: The complete RFC 822 message bytes.
    ///   - mailbox: The destination mailbox path (e.g. "Sent").
    ///   - flags: Flags to set on the appended message.
    ///   - internalDate: Optional internal date to store on the server.
    /// - Returns: ``AppendResult`` describing server-assigned identifiers.
    @discardableResult
    public func append(
        rawMessage: Data,
        to mailbox: String,
        flags: [Flag],
        internalDate: Date?
    ) async throws -> AppendResult {
        let command = try AppendCommand(
            mailboxName: resolveMailboxPath(mailbox), message: rawMessage, flags: flags,
            date: internalDate, appendLimit: capabilities.globalAppendLimit
        )
        return try await executeCommand(command)
    }

    /**
     Append a fully composed email to a mailbox.

     This helper builds the MIME body using ``Email/constructContent(use8BitMIME:)``
     and streams it to the server using the IMAP `APPEND` command.

     - Parameters:
        - email: The email to append.
        - mailbox: The destination mailbox path (e.g. "Drafts").
        - flags: Optional message flags to set during append.
        - internalDate: Optional internal date to store on the server. Defaults to the server-provided date.
     - Returns: ``AppendResult`` describing server-assigned identifiers.
     */
    @discardableResult
    public func append(
        email: Email,
        to mailbox: String,
        flags: [Flag] = [],
        internalDate: Date? = nil
    ) async throws -> AppendResult {
        guard !mailbox.isEmpty else {
            throw IMAPError.invalidArgument("Mailbox name must not be empty")
        }

        var content = canonicalizeCRLF(email.constructContent(use8BitMIME: true))
        if !content.hasSuffix("\r\n") {
            content.append("\r\n")
        }

        return try await append(rawMessage: content, to: mailbox, flags: flags, internalDate: internalDate)
    }

    /**
     Create a brand-new draft message by appending the provided email to the drafts mailbox.

     The method automatically sets the `\\Draft` flag and relies on the server's drafts mailbox if no
     custom mailbox is supplied.

     - Parameters:
        - email: The email content to store as a draft.
        - mailbox: Optional custom mailbox path. Defaults to the detected drafts mailbox.
        - date: Optional internal date to stamp on the message.
        - additionalFlags: Extra flags to include alongside `\\Draft`.
     - Returns: ``AppendResult`` describing server-assigned identifiers.
     */
    @discardableResult
    public func createDraft(
        from email: Email,
        in mailbox: String? = nil,
        date: Date? = nil,
        additionalFlags: [Flag] = []
    ) async throws -> AppendResult {
        var flags: [Flag] = [.draft]
        flags.append(contentsOf: additionalFlags)

        let targetMailbox: String
        if let mailbox {
            targetMailbox = mailbox
        } else {
            targetMailbox = try draftsFolder.name
        }

        // Mark as a draft so mail clients (e.g. Apple Mail) recognize ownership
        // and remove the message from Drafts after sending.
        var draft = email
        var headers = draft.additionalHeaders ?? [:]
        if headers["X-Uniform-Type-Identifier"] == nil {
            headers["X-Uniform-Type-Identifier"] = "com.apple.mail-draft"
        }
        draft.additionalHeaders = headers

        return try await append(email: draft, to: targetMailbox, flags: flags, internalDate: date)
    }
}
