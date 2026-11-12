import XCTest
import CoreGraphics
@testable import EyeWatchCore

final class SystemInputIdleTests: XCTestCase {
    func testSelectorIncludesAllRealInputInsteadOfNullEvents() {
        XCTAssertEqual(SystemInputIdle.eventType.rawValue, UInt32.max)
        XCTAssertNotEqual(SystemInputIdle.eventType, .null)
    }
    func testAnyInputIdleIsNoOlderThanRecentMouseInput() {
        // Read the specific event first so real input arriving during the probe cannot falsify the bound.
        let mouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let anyIdle = SystemInputIdle.read()
        XCTAssertTrue(anyIdle.isFinite && anyIdle >= 0)
        XCTAssertLessThanOrEqual(anyIdle, min(mouseIdle, keyboardIdle) + 1)
    }
}
