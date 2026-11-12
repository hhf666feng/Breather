import XCTest
@testable import EyeWatchCore

final class MonitorTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var start: Date { Date(timeIntervalSince1970: 1_735_732_800) }
    func settings() -> MonitorSettings { var s = MonitorSettings(); s.workSeconds = 60; s.restSeconds = 20; s.idleSeconds = 10; return s }
    func testActiveUseTriggersBreakAtInterval() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        for n in 1...60 { engine.tick(at: start.addingTimeInterval(Double(n)), idleSeconds: 0) }
        XCTAssertEqual(engine.phase, .resting)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 60, accuracy: 0.01)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksOffered, 1)
        XCTAssertEqual(engine.fatigue, 100, accuracy: 0.01)
    }
    func testIdleRecoversWithoutCountingScreenTime() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.tick(at: start.addingTimeInterval(5), idleSeconds: 0)
        engine.tick(at: start.addingTimeInterval(10), idleSeconds: 20)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 5)
        XCTAssertLessThan(engine.fatigue, 5.0 / 60 * 100)
        XCTAssertEqual(engine.phase, .idle)
    }
    func testRestCompletionIsCountedOnceAndResetsFatigue() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.startBreak(at: start)
        for n in 1...25 { engine.tick(at: start.addingTimeInterval(Double(n)), idleSeconds: 0) }
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksCompleted, 1)
        XCTAssertEqual(engine.phase, .monitoring)
        XCTAssertLessThan(engine.fatigue, 10)
    }
    func testStrictModeRefusesSkip() {
        var s = settings(); s.strictMode = true
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.startBreak(at: start)
        XCTAssertFalse(engine.skipBreak(at: start))
        XCTAssertEqual(engine.phase, .resting)
    }
    func testSkipDoesNotPretendBreakWasCompleted() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.startBreak(at: start)
        XCTAssertTrue(engine.skipBreak(at: start))
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksCompleted, 0)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksSkipped, 1)
    }
    func testSnoozeAllowsActiveTrackingAndExpires() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.snooze(until: start.addingTimeInterval(70))
        for n in 1...69 { engine.tick(at: start.addingTimeInterval(Double(n)), idleSeconds: 0) }
        XCTAssertEqual(engine.phase, .snoozed)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 69)
        engine.tick(at: start.addingTimeInterval(70), idleSeconds: 0)
        XCTAssertEqual(engine.phase, .resting)
    }
    func testSleepSizedGapsDoNotAccumulateUsage() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.tick(at: start.addingTimeInterval(3600), idleSeconds: 0)
        XCTAssertEqual(engine.records.reduce(0) { $0 + $1.activeSeconds }, 0)
        XCTAssertEqual(engine.fatigue, 0)
    }
    func testPausedTimeDoesNotAccumulate() {
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.setPaused(true, at: start)
        engine.tick(at: start.addingTimeInterval(5), idleSeconds: 0)
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertTrue(engine.records.isEmpty)
        engine.setPaused(false, at: start.addingTimeInterval(5))
        engine.tick(at: start.addingTimeInterval(10), idleSeconds: 0)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 5)
    }
    func testMidnightSplitsUsageAcrossDates() {
        let midnight = calendar.startOfDay(for: start).addingTimeInterval(86400)
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: midnight.addingTimeInterval(-2), idleSeconds: 0)
        engine.tick(at: midnight.addingTimeInterval(2), idleSeconds: 0)
        XCTAssertEqual(engine.records.count, 2)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 2)
        XCTAssertEqual((engine.records.dropFirst().first ?? DailyRecord(day: "missing")).activeSeconds, 2)
    }
    func testOvernightScheduleUsesPreviousWeekdayAfterMidnight() {
        var s = settings(); s.scheduleEnabled = true; s.scheduleStartHour = 22; s.scheduleEndHour = 6; s.weekdays = [4] // Wednesday, Jan 1 2025
        let wed = calendar.startOfDay(for: start)
        XCTAssertTrue(s.isScheduled(at: wed.addingTimeInterval(23 * 3600), calendar: calendar))
        XCTAssertTrue(s.isScheduled(at: wed.addingTimeInterval(26 * 3600), calendar: calendar))
        XCTAssertFalse(s.isScheduled(at: wed.addingTimeInterval(34 * 3600), calendar: calendar))
        XCTAssertFalse(s.isScheduled(at: wed.addingTimeInterval(50 * 3600), calendar: calendar))
    }
    func testPersistenceRoundTripAndCSVContainsActualMetrics() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(directory: dir)
        var engine = MonitorEngine(settings: settings(), calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.tick(at: start.addingTimeInterval(5), idleSeconds: 0)
        try store.save(settings: engine.settings, records: engine.records)
        let loaded = try store.load()
        XCTAssertEqual(loaded.settings.workSeconds, 60)
        XCTAssertEqual(loaded.records.first?.activeSeconds, 5)
        XCTAssertTrue(CSVExporter.render(loaded.records).contains("2025-01-01,5"))
    }
    func testStrictBreakCannotBeCancelledByPausing() {
        var s = settings(); s.strictMode = true
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.startBreak(at: start)
        engine.setPaused(true, at: start)
        XCTAssertEqual(engine.phase, .resting)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksSkipped, 0)
    }
    func testNotificationReminderDoesNotCountAsCompletedPopupRest() {
        var s = settings(); s.reminderStyle = .notification
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        for n in 1...81 { engine.tick(at: start.addingTimeInterval(Double(n)), idleSeconds: 0) }
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksOffered, 0)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).breaksCompleted, 0)
        XCTAssertEqual(engine.phase, .monitoring)
        XCTAssertEqual(engine.fatigue, 100, accuracy: 0.01)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 81)
    }
    func testOlderSettingsSchemaRetainsDataAndAddsDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"settings":{"workSeconds":600},"records":[]}"#.utf8).write(to: dir.appendingPathComponent("state.json"))
        let state = try LocalStore(directory: dir).load()
        XCTAssertEqual(state.settings.workSeconds, 600)
        XCTAssertEqual(state.settings.monitoringMode, .smart)
        XCTAssertEqual(state.settings.restSeconds, 20)
    }
    func testPeakUsageOnlyCountsAtOneHundredPercent() {
        var s = settings(); s.fatigueThreshold = 50
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.snooze(until: start.addingTimeInterval(1000))
        for n in 1...45 { engine.tick(at: start.addingTimeInterval(Double(n)), idleSeconds: 0) }
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).peakFatigueSeconds, 0)
    }
    func testContinuousModeCountsReadingWithoutMouseMovement() {
        var s = settings(); s.monitoringMode = .continuous
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.tick(at: start, idleSeconds: 100)
        engine.tick(at: start.addingTimeInterval(5), idleSeconds: 105)
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 5)
        XCTAssertEqual(engine.phase, .monitoring)
    }
    func testScheduleOnlySuppressesRemindersNotActualUsage() {
        var s = settings(); s.scheduleEnabled = true; s.scheduleStartHour = 8; s.scheduleEndHour = 9; s.weekdays = Set(1...7)
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        for n in 1...61 { engine.tick(at: start.addingTimeInterval(Double(n)), idleSeconds: 0) }
        XCTAssertEqual((engine.records.first ?? DailyRecord(day: "missing")).activeSeconds, 61)
        XCTAssertEqual(engine.phase, .outsideSchedule)
        XCTAssertEqual(engine.fatigue, 100, accuracy: 0.01)
    }
    func testShortLockDoesNotCountAsActiveUsage() {
        var s = settings(); s.monitoringMode = .continuous
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.tick(at: start, idleSeconds: 0)
        engine.tick(at: start.addingTimeInterval(5), idleSeconds: 0, screenAvailable: false)
        XCTAssertEqual(engine.records.reduce(0) { $0 + $1.activeSeconds }, 0)
        XCTAssertEqual(engine.phase, .idle)
    }
    func testStrictnessAppliesToTheWholeCurrentBreak() {
        var s = settings(); s.strictMode = true
        var engine = MonitorEngine(settings: s, calendar: calendar)
        engine.startBreak(at: start)
        engine.settings.strictMode = false
        XCTAssertFalse(engine.skipBreak(at: start))
        engine.setPaused(true, at: start)
        engine.snooze(until: start.addingTimeInterval(60))
        XCTAssertEqual(engine.phase, .resting)
    }
    func testCorruptCounterValuesThrowInsteadOfOverflowing() throws {
        let hours = Array(repeating: "0", count: 24).joined(separator: ",")
        let json = "{\"settings\":{},\"records\":[{\"day\":\"2025-01-01\",\"activeSeconds\":0,\"peakFatigueSeconds\":0,\"breaksOffered\":\(Int.max),\"breaksCompleted\":\(Int.max),\"breaksSkipped\":1,\"hourlySeconds\":[\(hours)]}]}"
        XCTAssertThrowsError(try LocalStore.decode(Data(json.utf8)))
    }
    func testInvalidSettingsAreClamped() {
        var s = settings(); s.workSeconds = -10; s.restSeconds = 0; s.fatigueThreshold = 200
        let clean = s.validated()
        XCTAssertGreaterThan(clean.workSeconds, 0)
        XCTAssertGreaterThan(clean.restSeconds, 0)
        XCTAssertEqual(clean.fatigueThreshold, 100)
    }
}
