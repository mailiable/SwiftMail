import NIO
import NIOIMAP
import NIOIMAPCore

/// Searches the selected Gmail mailbox by Gmail's stable, cross-mailbox message ID.
struct SearchGmailMessageIDCommand: IMAPTaggedCommand, Sendable {
    typealias ResultType = UIDSet
    typealias HandlerType = SearchHandler<UID>

    let messageID: UInt64

    var timeoutSeconds: Int { 60 }

    func toTaggedCommand(tag: String) -> TaggedCommand {
        TaggedCommand(
            tag: tag,
            command: .custom(
                name: "UID SEARCH",
                payloads: [
                    .verbatim(ByteBuffer(string: "X-GM-MSGID \(messageID)"))
                ]
            )
        )
    }
}
