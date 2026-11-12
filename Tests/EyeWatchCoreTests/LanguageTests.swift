import XCTest
@testable import EyeWatchCore

final class LanguageTests: XCTestCase {
    func testLanguageSelectionUsesEnglishImmediately() {
        XCTAssertEqual(AppLanguage.english.choose("今日", "Today"), "Today")
        XCTAssertEqual(AppLanguage.chinese.choose("今日", "Today"), "今日")
    }
    func testStoredLanguageCodesAreStable() throws {
        let encoded = try JSONEncoder().encode(AppLanguage.english)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"en\"")
        XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: encoded), .english)
        XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: Data("\"fr\"".utf8)), .chinese)
    }
    func testDateLocaleFollowsLanguageChoice() {
        XCTAssertEqual(AppLanguage.english.locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(AppLanguage.chinese.locale.language.languageCode?.identifier, "zh")
    }
    func testDurationsUseLocalizedUnitsAndTabularFormatting() {
        XCTAssertEqual(AppLanguage.english.duration(7500), "2h 05m")
        XCTAssertEqual(AppLanguage.chinese.duration(7500), "2时 05分")
        XCTAssertEqual(AppLanguage.english.duration(59), "0 min")
        XCTAssertEqual(AppLanguage.chinese.duration(120), "2 分钟")
        XCTAssertEqual(AppLanguage.english.duration(-1), "0 min")
        XCTAssertEqual(AppLanguage.english.duration(.infinity), "0 min")
    }
    func testDefaultRestMessageIsLocalizedWithoutChangingCustomText() {
        let original = MonitorSettings().restMessage
        XCTAssertEqual(AppLanguage.english.restMessage(original), "Look into the distance and step away from the screen")
        XCTAssertEqual(AppLanguage.chinese.restMessage(original), original)
        XCTAssertEqual(AppLanguage.english.restMessage("会后记得喝水"), "会后记得喝水")
        XCTAssertEqual(AppLanguage.chinese.restMessage("Take a breath"), "Take a breath")
    }
    func testLanguageSurvivesSaveAndLoadWithHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(directory: dir)
        var settings = MonitorSettings(); settings.language = .english; settings.workSeconds = 600
        var record = DailyRecord(day: "2026-11-06"); record.activeSeconds = 120; record.hourlySeconds[9] = 120
        try store.save(settings: settings, records: [record])
        let loaded = try store.load()
        XCTAssertEqual(loaded.settings.language, .english)
        XCTAssertEqual(loaded.settings.workSeconds, 600)
        XCTAssertEqual(loaded.records, [record])
    }
    func testOldBackupDefaultsToChineseAndPreservesSettings() throws {
        let data = Data(#"{"settings":{"workSeconds":600},"records":[]}"#.utf8)
        let loaded = try LocalStore.decode(data)
        XCTAssertEqual(loaded.settings.language, .chinese)
        XCTAssertEqual(loaded.settings.workSeconds, 600)
    }
    func testUnknownLanguageDoesNotDiscardValidHistory() throws {
        let data = Data(#"{"settings":{"language":"fr","restMessage":"Custom","workSeconds":600},"records":[]}"#.utf8)
        let loaded = try LocalStore.decode(data)
        XCTAssertEqual(loaded.settings.language, .chinese)
        XCTAssertEqual(loaded.settings.restMessage, "Custom")
        XCTAssertEqual(loaded.settings.workSeconds, 600)
    }
}
