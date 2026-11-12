import XCTest
@testable import EyeWatchCore

final class DockVisibilityTests: XCTestCase {
    private func flag(in settings: MonitorSettings) throws -> Bool? {
        let data = try JSONEncoder().encode(settings)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["showDockIcon"] as? Bool
    }
    func testHiddenDockPreferenceSurvivesBackupAndRestart() throws {
        let data = Data(#"{"settings":{"showDockIcon":false,"language":"en","workSeconds":600},"records":[]}"#.utf8)
        let state = try LocalStore.decode(data)
        XCTAssertEqual(try flag(in: state.settings), false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(directory: directory)
        try store.save(settings: state.settings, records: state.records)
        let reloaded = try store.load()
        XCTAssertEqual(try flag(in: reloaded.settings), false)
        XCTAssertEqual(reloaded.settings.language, .english)
        XCTAssertEqual(reloaded.settings.workSeconds, 600)
    }
    func testOlderSettingsKeepDockVisibleByDefault() throws {
        let data = Data(#"{"settings":{"language":"zh-Hans","workSeconds":900},"records":[]}"#.utf8)
        let state = try LocalStore.decode(data)
        XCTAssertEqual(try flag(in: state.settings), true)
        XCTAssertEqual(state.settings.workSeconds, 900)
    }
}
