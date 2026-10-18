@testable import Switchboard
import XCTest

final class SwitchRulesTests: XCTestCase {
    func testOtherScreenIsDisabledInEitherMode() {
        XCTAssertEqual(Switcher.action(isLastRealDisplay: false, mode: .sleep), .disable)
        XCTAssertEqual(Switcher.action(isLastRealDisplay: false, mode: .keepRunning), .disable)
    }

    func testLastScreenStaysOnAndMacSleeps() {
        XCTAssertEqual(Switcher.action(isLastRealDisplay: true, mode: .sleep), .keepAndSleep)
    }

    func testLastScreenStaysOnAndMacKeepsRunning() {
        XCTAssertEqual(Switcher.action(isLastRealDisplay: true, mode: .keepRunning), .keepRunning)
    }
}
