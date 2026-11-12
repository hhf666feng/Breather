import XCTest
@testable import EyeWatchCore

final class ActivityDetectionTests: XCTestCase {
    private var enabled: MonitorSettings { var s = MonitorSettings(); s.enhancedInputDetection = true; s.screenActivityDetection = true; return s }
    func testPermissionlessSystemIdleRemainsTheFallback() {
        let s = ActivitySignals(systemIdleSeconds: 120, inputIdleSeconds: 0, screenChangeIdleSeconds: 0)
        let result = ActivityClassifier.evaluate(s, settings: enabled, screenAvailable: true)
        XCTAssertEqual(result.source, .idle)
        XCTAssertEqual(result.idleSeconds, 120)
    }
    func testEnhancedInputRequiresEnablePermissionAndRunningMonitor() {
        var signals = ActivitySignals(systemIdleSeconds: 120, inputIdleSeconds: 1, accessibilityGranted: true, inputMonitorRunning: true)
        XCTAssertEqual(ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true).source, .enhancedInput)
        XCTAssertEqual(ActivityClassifier.evaluate(signals, settings: MonitorSettings(), screenAvailable: true).source, .idle)
        signals.accessibilityGranted = false
        XCTAssertEqual(ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true).source, .idle)
        signals.accessibilityGranted = true; signals.inputMonitorRunning = false
        XCTAssertEqual(ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true).source, .idle)
    }
    func testRecentScreenChangesKeepVideoUseActive() {
        let signals = ActivitySignals(systemIdleSeconds: 600, screenChangeIdleSeconds: 2, screenRecordingGranted: true, screenMonitorRunning: true)
        let result = ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true)
        XCTAssertEqual(result.source, .screenChanges)
        XCTAssertEqual(result.idleSeconds, 2)
    }
    func testRevokedOrStoppedScreenCaptureCannotSupplyActivity() {
        var signals = ActivitySignals(systemIdleSeconds: 600, screenChangeIdleSeconds: 0, screenRecordingGranted: true, screenMonitorRunning: false)
        XCTAssertEqual(ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true).source, .idle)
        signals.screenMonitorRunning = true; signals.screenRecordingGranted = false
        XCTAssertEqual(ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true).source, .idle)
    }
    func testStaleEnhancedSignalsExpireInsteadOfHoldingUsageActive() {
        let signals = ActivitySignals(systemIdleSeconds: 600, inputIdleSeconds: 120, screenChangeIdleSeconds: 180, accessibilityGranted: true, inputMonitorRunning: true, screenRecordingGranted: true, screenMonitorRunning: true)
        let result = ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true)
        XCTAssertEqual(result.source, .idle)
        XCTAssertGreaterThanOrEqual(result.idleSeconds, enabled.idleSeconds)
    }
    func testScreenUnavailableOverridesEverySignalAndContinuousMode() {
        var settings = enabled; settings.monitoringMode = .continuous
        let signals = ActivitySignals(systemIdleSeconds: 0, inputIdleSeconds: 0, screenChangeIdleSeconds: 0, accessibilityGranted: true, inputMonitorRunning: true, screenRecordingGranted: true, screenMonitorRunning: true)
        let result = ActivityClassifier.evaluate(signals, settings: settings, screenAvailable: false)
        XCTAssertEqual(result.source, .unavailable)
        XCTAssertFalse(result.screenAvailable)
        XCTAssertGreaterThanOrEqual(result.idleSeconds, settings.idleSeconds)
    }
    func testContinuousModeExplicitlyCountsStaticReading() {
        var settings = MonitorSettings(); settings.monitoringMode = .continuous
        let result = ActivityClassifier.evaluate(.init(systemIdleSeconds: 600), settings: settings, screenAvailable: true)
        XCTAssertEqual(result.source, .continuous)
        XCTAssertEqual(result.idleSeconds, 0)
    }
    func testInvalidSignalsNeverTurnMissingDataIntoActivity() {
        let signals = ActivitySignals(systemIdleSeconds: .nan, inputIdleSeconds: .infinity, screenChangeIdleSeconds: .nan, accessibilityGranted: true, inputMonitorRunning: true, screenRecordingGranted: true, screenMonitorRunning: true)
        let result = ActivityClassifier.evaluate(signals, settings: enabled, screenAvailable: true)
        XCTAssertEqual(result.source, .idle)
        XCTAssertTrue(result.idleSeconds.isFinite)
        XCTAssertGreaterThanOrEqual(result.idleSeconds, enabled.idleSeconds)
    }
    func testRealSystemInputDoesNotNeedAdditionalPermissions() {
        let result = ActivityClassifier.evaluate(.init(systemIdleSeconds: 3), settings: MonitorSettings(), screenAvailable: true)
        XCTAssertEqual(result.source, .systemInput)
        XCTAssertEqual(result.idleSeconds, 3)
    }
    func testFirstFrameAndChangedSizeAreOnlyBaselines() {
        var detector = ScreenChangeDetector()
        XCTAssertFalse(detector.observe(Array(repeating: 10, count: 100)))
        XCTAssertFalse(detector.observe(Array(repeating: 200, count: 64)))
    }
    func testNoiseAndSmallClockChangesAreIgnored() {
        var detector = ScreenChangeDetector()
        XCTAssertFalse(detector.observe(Array(repeating: 100, count: 100)))
        XCTAssertFalse(detector.observe(Array(repeating: 101, count: 100)))
        var clock = Array(repeating: UInt8(101), count: 100); clock[0] = 255
        XCTAssertFalse(detector.observe(clock))
    }
    func testMaterialMotionIsDetectedAndResetDoesNotInventActivity() {
        var detector = ScreenChangeDetector()
        XCTAssertFalse(detector.observe(Array(repeating: 0, count: 100)))
        var motion = Array(repeating: UInt8(0), count: 100)
        for index in 0..<30 { motion[index] = 120 }
        XCTAssertTrue(detector.observe(motion))
        XCTAssertFalse(detector.observe(motion))
        detector.reset()
        XCTAssertFalse(detector.observe(Array(repeating: 200, count: 100)))
    }
    func testNewDetectionOptionsAreOptInAndSurviveBackup() throws {
        let legacy = try LocalStore.decode(Data(#"{"settings":{"language":"en"},"records":[]}"#.utf8))
        XCTAssertFalse(legacy.settings.enhancedInputDetection)
        XCTAssertFalse(legacy.settings.screenActivityDetection)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(directory: dir)
        try store.save(settings: enabled, records: [])
        let loaded = try store.load()
        XCTAssertTrue(loaded.settings.enhancedInputDetection)
        XCTAssertTrue(loaded.settings.screenActivityDetection)
    }
}
