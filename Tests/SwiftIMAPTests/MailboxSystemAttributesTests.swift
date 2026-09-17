import CustomDump
import NIOIMAPCore
import Testing
@testable import SwiftMail

struct MailboxSystemAttributesTests {
    // Detects All Mail being exposed as an ordinary user mailbox after LIST.
    @Test func allMailRetainsItsSystemAttribute() {
        let attributes = SwiftMail.Mailbox.Info.Attributes(from: [.init("\\All")])
        expectNoDifference(attributes, .all)
    }

    // Detects Important being exposed as an ordinary user mailbox after LIST.
    @Test func importantRetainsItsSystemAttribute() {
        let attributes = SwiftMail.Mailbox.Info.Attributes(from: [.init("\\Important")])
        expectNoDifference(attributes, .important)
    }
}
