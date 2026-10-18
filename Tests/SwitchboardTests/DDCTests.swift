@testable import Switchboard
import XCTest

/// Get VCP replies from the MCCS spec: source, length, opcode 0x02, result, VCP code, type,
/// maximum (2 bytes), current value (2 bytes), checksum (0x50 XOR the other bytes).
final class DDCTests: XCTestCase {
    func testAcceptsInputReply() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x12, 0x00, 0x0F, 0xC9]
        XCTAssertTrue(DDC.isReply(reply, to: 0x60))
    }

    /// A busy monitor's null message has a valid checksum but no value.
    func testRejectsNullMessage() {
        let reply: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertFalse(DDC.isReply(reply, to: 0x60))
    }

    /// Result 0x01 means the monitor does not support the VCP code.
    func testRejectsUnsupportedCode() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD5]
        XCTAssertFalse(DDC.isReply(reply, to: 0x60))
    }
}
