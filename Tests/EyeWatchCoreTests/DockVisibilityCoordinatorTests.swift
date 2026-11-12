import XCTest
@testable import EyeWatchCore

final class DockVisibilityCoordinatorTests: XCTestCase {
    func testPersistentOSRejectionIsAttemptedOnceAcrossThousandsOfStatusUpdates() {
        var coordinator = DockVisibilityCoordinator()
        var attempts = 0
        for _ in 0..<10_000 {
            XCTAssertFalse(coordinator.apply(requested: true, current: false) { _ in attempts += 1; return false })
        }
        XCTAssertEqual(attempts, 1, "OS failure must not create an async status/persistence feedback loop")
    }
    func testAlreadyMatchingPolicyDoesNotCallTheOS() {
        var coordinator = DockVisibilityCoordinator()
        var attempts = 0
        XCTAssertFalse(coordinator.apply(requested: false, current: false) { _ in attempts += 1; return false })
        XCTAssertEqual(attempts, 0)
    }
    func testNewPreferenceCanBeAppliedAfterRejectedRequest() {
        var coordinator = DockVisibilityCoordinator()
        var attempts = 0
        XCTAssertFalse(coordinator.apply(requested: true, current: false) { _ in attempts += 1; return false })
        XCTAssertFalse(coordinator.apply(requested: false, current: false) { _ in attempts += 1; return false })
        XCTAssertTrue(coordinator.apply(requested: true, current: false) { _ in attempts += 1; return true })
        XCTAssertEqual(attempts, 2)
    }
    func testSuccessfulTransitionIsIdempotent() {
        var coordinator = DockVisibilityCoordinator()
        var attempts = 0
        XCTAssertTrue(coordinator.apply(requested: false, current: true) { _ in attempts += 1; return true })
        XCTAssertFalse(coordinator.apply(requested: false, current: false) { _ in attempts += 1; return true })
        XCTAssertEqual(attempts, 1)
    }
}
