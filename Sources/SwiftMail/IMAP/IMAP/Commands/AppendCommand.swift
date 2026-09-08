import Foundation
import NIO
import NIOIMAP
import NIOIMAPCore

/// Command for appending a message to a mailbox.
struct AppendCommand: IMAPCommand {
    typealias ResultType = AppendResult
    typealias HandlerType = AppendHandler

    let mailboxName: String
    let message: Data
    let flags: [Flag]
    let internalDate: ServerMessageDate?

    var timeoutSeconds: Int { return 30 }

    func validate() throws {
        guard !mailboxName.isEmpty else {
            throw IMAPError.invalidArgument("Mailbox name must not be empty")
        }
    }

    func send(on channel: Channel, tag: String) async throws {
        var messageBuffer = channel.allocator.buffer(capacity: message.count)
        messageBuffer.writeBytes(message)

        var mailboxBuffer = channel.allocator.buffer(capacity: mailboxName.utf8.count)
        mailboxBuffer.writeString(mailboxName)
        let mailbox = MailboxName(mailboxBuffer)

        let nioFlags = flags.map { $0.toNIO() }
        let appendOptions = AppendOptions(flagList: nioFlags, internalDate: internalDate)
        let metadata = AppendMessage(options: appendOptions, data: AppendData(byteCount: messageBuffer.readableBytes))

        channel.write(IMAPClientHandler.OutboundIn.part(.append(.start(tag: tag, appendingTo: mailbox))), promise: nil)
        channel.write(IMAPClientHandler.OutboundIn.part(.append(.beginMessage(message: metadata))), promise: nil)
        // Flush APPEND metadata first so servers can respond with literal continuation.
        channel.flush()

        // Do not await write promises here. These writes may be continuation-gated by the IMAP state machine,
        // and awaiting them can deadlock this command send path until timeout.
        channel.write(IMAPClientHandler.OutboundIn.part(.append(.messageBytes(messageBuffer))), promise: nil)
        channel.write(IMAPClientHandler.OutboundIn.part(.append(.endMessage)), promise: nil)
        channel.writeAndFlush(IMAPClientHandler.OutboundIn.part(.append(.finish)), promise: nil)
    }
}

// Both primary and named connections use the same limit check and date conversion.
extension AppendCommand {
    init(mailboxName: String, message: Data, flags: [Flag], date: Date?, appendLimit: Int?) throws {
        if let limit = appendLimit, message.count > limit {
            throw IMAPError.appendLimitExceeded(message.count, limit)
        }
        self.init(mailboxName: mailboxName, message: message, flags: flags,
                  internalDate: date.flatMap(makeInternalDate(from:)))
    }
}

private func makeInternalDate(from date: Date) -> ServerMessageDate? {
    var calendar = Calendar(identifier: .gregorian)
    let timeZone = TimeZone.current
    calendar.timeZone = timeZone

    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard
        let year = components.year,
        let month = components.month,
        let day = components.day,
        let hour = components.hour,
        let minute = components.minute
    else {
        return nil
    }

    let second = components.second ?? 0
    let zoneMinutes = timeZone.secondsFromGMT(for: date) / 60

    guard let serverComponents = ServerMessageDate.Components(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        timeZoneMinutes: zoneMinutes
    ) else {
        return nil
    }

    return ServerMessageDate(serverComponents)
}
