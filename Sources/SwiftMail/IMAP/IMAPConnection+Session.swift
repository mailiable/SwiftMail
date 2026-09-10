import Foundation

extension IMAPConnection {
    /// Called while the command queue is held. Bootstrap commands use the same
    /// queue, so another caller cannot send a command partway through restoration.
    func prepareSession(restoringMailbox: Bool = true) async throws {
        guard !isPreparingSession else { return }
        isPreparingSession = true
        defer { isPreparingSession = false }

        clearInvalidChannel()
        if channel == nil {
            try await connectBody()
        }
        if !isSessionAuthenticated, let authenticateSession {
            try await authenticateSession(self)
        }
        guard restoringMailbox, mailboxNeedsSelection, let selectedMailbox else { return }

        let selection: Mailbox.Selection
        if selectedMailbox.readOnly {
            selection = try await executeCommand(ExamineMailboxCommand(mailboxName: selectedMailbox.name))
        } else {
            selection = try await executeCommand(SelectMailboxCommand(mailboxName: selectedMailbox.name))
        }
        guard selection.uidValidity == selectedMailbox.uidValidity else {
            throw IMAPError.commandFailed(
                "Mailbox UID validity changed after reconnect; "
                    + "select the mailbox again before using message identifiers"
            )
        }
        mailboxNeedsSelection = false
    }

    func recordMailboxSelection<Command: IMAPCommand>(command: Command, result: Command.ResultType) {
        guard !isPreparingSession else { return }
        if let selection = result as? Mailbox.Selection {
            if let command = command as? SelectMailboxCommand {
                selectedMailbox = .init(name: command.mailboxName, readOnly: false, uidValidity: selection.uidValidity)
                mailboxNeedsSelection = false
            } else if let command = command as? ExamineMailboxCommand {
                selectedMailbox = .init(name: command.mailboxName, readOnly: true, uidValidity: selection.uidValidity)
                mailboxNeedsSelection = false
            }
        } else if command is CloseCommand || command is UnselectCommand {
            selectedMailbox = nil
            mailboxNeedsSelection = false
        }
    }
}
