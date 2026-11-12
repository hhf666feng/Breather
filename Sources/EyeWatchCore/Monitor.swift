import Foundation

public enum MonitorPhase: String, Codable { case monitoring, idle, resting, paused, snoozed, outsideSchedule }
public enum ReminderStyle: String, Codable, CaseIterable, Identifiable {
    case fullscreen, mini, notification
    public var id: String { rawValue }
    public var title: String { switch self { case .fullscreen: return "全屏休息"; case .mini: return "迷你浮窗"; case .notification: return "系统通知" } }
}
public enum MonitoringMode: String, Codable, CaseIterable, Identifiable {
    case smart, continuous
    public var id: String { rawValue }
    public var title: String { self == .smart ? "智能检测" : "阅读 / 观影" }
}
public enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}
public struct MonitorSettings: Codable, Equatable {
    public var language: AppLanguage = .chinese
    public var enhancedInputDetection = false
    public var screenActivityDetection = false
    public var monitoringMode: MonitoringMode = .smart
    public var theme: AppTheme = .system
    public var backupDirectory: String?
    public var skipChallengeEnabled = false
    public var dailyLimitEnabled = false
    public var dailyLimitHours: Double = 8
    public var advanceNoticeEnabled = false
    public var workSeconds: Double = 1200
    public var restSeconds: Double = 20
    public var idleSeconds: Double = 60
    public var fatigueThreshold: Double = 100
    public var strictMode = false
    public var soundEnabled = true
    public var reminderStyle: ReminderStyle = .fullscreen
    public var scheduleEnabled = false
    public var scheduleStartHour = 9
    public var scheduleEndHour = 18
    public var weekdays: Set<Int> = [2,3,4,5,6]
    public var restMessage = "望向远处，暂时离开屏幕"
    public var wallpaperPath: String?
    public var showMenuBarTime = true
    public var showDockIcon = true
    public init() {}
    public func validated() -> Self {
        var s = self
        s.workSeconds = workSeconds.isFinite ? min(14400, max(10, workSeconds)) : 1200
        s.restSeconds = restSeconds.isFinite ? min(3600, max(5, restSeconds)) : 20
        s.idleSeconds = idleSeconds.isFinite ? min(600, max(5, idleSeconds)) : 60
        s.fatigueThreshold = fatigueThreshold.isFinite ? min(100, max(10, fatigueThreshold)) : 100
        s.dailyLimitHours = dailyLimitHours.isFinite ? min(24, max(0.5, dailyLimitHours)) : 8
        s.scheduleStartHour = min(23, max(0, scheduleStartHour))
        s.scheduleEndHour = min(23, max(0, scheduleEndHour))
        s.weekdays = weekdays.intersection(Set(1...7))
        return s
    }
    public func isScheduled(at date: Date, calendar: Calendar = .current) -> Bool {
        guard scheduleEnabled else { return true }
        let hour = calendar.component(.hour, from: date)
        var weekday = calendar.component(.weekday, from: date)
        if scheduleStartHour == scheduleEndHour { return weekdays.contains(weekday) }
        if scheduleStartHour < scheduleEndHour {
            return weekdays.contains(weekday) && hour >= scheduleStartHour && hour < scheduleEndHour
        }
        if hour < scheduleEndHour { weekday = weekday == 1 ? 7 : weekday - 1 }
        return weekdays.contains(weekday) && (hour >= scheduleStartHour || hour < scheduleEndHour)
    }
}
public struct DailyRecord: Codable, Identifiable, Equatable {
    public var day: String
    public var activeSeconds: Double = 0
    public var peakFatigueSeconds: Double = 0
    public var breaksOffered = 0
    public var breaksCompleted = 0
    public var breaksSkipped = 0
    public var hourlySeconds: [Double] = Array(repeating: 0, count: 24)
    public var id: String { day }
    public var completionRate: Double { breaksOffered == 0 ? 0 : Double(breaksCompleted) / Double(breaksOffered) }
    public init(day: String) { self.day = day }
}
public struct MonitorEngine {
    public var settings: MonitorSettings
    public private(set) var records: [DailyRecord]
    public private(set) var phase: MonitorPhase = .monitoring
    public private(set) var fatigue: Double = 0
    public private(set) var workElapsed: Double = 0
    public private(set) var breakRemaining: Double = 0
    public private(set) var breakIsStrict = false
    public let calendar: Calendar
    public private(set) var notificationCount = 0
    private var lastNotification: Date?
    public private(set) var snoozeEnd: Date?
    private var lastTick: Date?
    private var breakEnd: Date?
    private var breakRecordDay: String?
    private var paused = false
    public init(settings: MonitorSettings = .init(), records: [DailyRecord] = [], calendar: Calendar = .current) {
        self.settings = settings.validated(); self.records = records.sorted { $0.day < $1.day }; self.calendar = calendar
    }
    public func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public mutating func tick(at date: Date, idleSeconds: Double, screenAvailable: Bool = true) {
        let previous = lastTick
        lastTick = date
        let rawDelta = max(0, previous.map { date.timeIntervalSince($0) } ?? 0)
        let delta = rawDelta <= 15 ? rawDelta : 0
        if paused { phase = .paused; return }
        if let end = breakEnd {
            breakRemaining = max(0, end.timeIntervalSince(date))
            if breakRemaining <= 0 {
                if let day = breakRecordDay { mutateRecord(day: day) { $0.breaksCompleted += 1 } }
                breakEnd = nil; breakRecordDay = nil; fatigue = 0; workElapsed = 0
                phase = .monitoring
            } else {
                phase = .resting
                fatigue = max(0, fatigue - delta * 100 / settings.restSeconds)
            }
            return
        }
        if rawDelta > 15 {
            fatigue = max(0, fatigue - rawDelta * 100 / settings.restSeconds)
            workElapsed = fatigue * settings.workSeconds / 100
        }
        if !screenAvailable || (settings.monitoringMode == .smart && idleSeconds >= settings.idleSeconds) {
            phase = .idle
            fatigue = max(0, fatigue - delta * 100 / settings.restSeconds)
            workElapsed = fatigue * settings.workSeconds / 100
            return
        }
        let wasAtPeak = fatigue >= 100 - 0.000001
        fatigue = min(100, fatigue + delta * 100 / settings.workSeconds)
        workElapsed = fatigue * settings.workSeconds / 100
        if let previous, delta > 0 { recordUsage(from: previous, to: date, atPeak: wasAtPeak) }
        if let end = snoozeEnd, date < end { phase = .snoozed; return }
        snoozeEnd = nil
        guard settings.isScheduled(at: date, calendar: calendar) else { phase = .outsideSchedule; return }
        phase = .monitoring
        if fatigue + 0.000001 >= settings.fatigueThreshold {
            if settings.reminderStyle == .notification {
                if lastNotification == nil || date.timeIntervalSince(lastNotification!) >= 300 {
                    notificationCount += 1; lastNotification = date
                }
            } else { startBreak(at: date) }
        } else if fatigue < settings.fatigueThreshold - 1 { lastNotification = nil }
    }
    public mutating func startBreak(at date: Date, countInStatistics: Bool = true) {
        guard breakEnd == nil else { return }
        paused = false; snoozeEnd = nil
        phase = .resting; breakRemaining = settings.restSeconds; breakIsStrict = settings.strictMode
        breakEnd = date.addingTimeInterval(settings.restSeconds)
        breakRecordDay = countInStatistics ? dayKey(date) : nil
        lastTick = date
        if countInStatistics { mutateRecord(day: dayKey(date)) { $0.breaksOffered += 1 } }
    }
    @discardableResult public mutating func skipBreak(at date: Date) -> Bool {
        guard phase == .resting, !breakIsStrict else { return false }
        cancelBreak()
        snoozeEnd = date.addingTimeInterval(300); phase = .snoozed; lastTick = date
        return true
    }
    public mutating func snooze(until date: Date) {
        guard !(phase == .resting && breakIsStrict) else { return }
        if breakEnd != nil { cancelBreak() }
        snoozeEnd = date; phase = .snoozed
    }
    public mutating func setPaused(_ value: Bool, at date: Date) {
        guard !(value && phase == .resting && breakIsStrict) else { return }
        if value && breakEnd != nil { cancelBreak() }
        paused = value; phase = value ? .paused : .monitoring; lastTick = date
    }
    public mutating func resetClock(at date: Date) { lastTick = date }
    private mutating func cancelBreak() {
        if let day = breakRecordDay { mutateRecord(day: day) { $0.breaksSkipped += 1 } }
        breakEnd = nil; breakRecordDay = nil; breakRemaining = 0
    }
    private mutating func mutateRecord(day: String, _ update: (inout DailyRecord) -> Void) {
        if let i = records.firstIndex(where: { $0.day == day }) { update(&records[i]) }
        else {
            var record = DailyRecord(day: day); update(&record); records.append(record)
            records.sort { $0.day < $1.day }
        }
    }
    private mutating func recordUsage(from start: Date, to end: Date, atPeak: Bool) {
        var cursor = start
        while cursor < end {
            let boundary = calendar.dateInterval(of: .hour, for: cursor)?.end ?? end
            let segmentEnd = min(end, boundary)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            let hour = calendar.component(.hour, from: cursor)
            mutateRecord(day: dayKey(cursor)) { record in
                record.activeSeconds += seconds
                if atPeak { record.peakFatigueSeconds += seconds }
                if record.hourlySeconds.count != 24 { record.hourlySeconds = Array(repeating: 0, count: 24) }
                record.hourlySeconds[hour] += seconds
            }
            cursor = segmentEnd
        }
    }
}
public struct StoredState: Codable { public var settings: MonitorSettings; public var records: [DailyRecord] }
public struct LocalStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(settings: MonitorSettings, records: [DailyRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(StoredState(settings: settings.validated(), records: records))
        try data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }
    public func load() throws -> StoredState {
        let url = directory.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return StoredState(settings: .init(), records: []) }
        return try Self.decode(Data(contentsOf: url))
    }
    public static func decode(_ data: Data) throws -> StoredState {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let saved = root["settings"] as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "备份中缺少有效的 settings 对象"))
        }
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MonitorSettings())) as! [String: Any]
        root["settings"] = defaults.merging(saved) { _, current in current }
        var state = try JSONDecoder().decode(StoredState.self, from: JSONSerialization.data(withJSONObject: root))
        state.settings = state.settings.validated()
        guard Set(state.records.map(\.day)).count == state.records.count,
              state.records.allSatisfy({ record in
                  record.day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil &&
                  record.activeSeconds.isFinite && record.activeSeconds >= 0 && record.activeSeconds <= 90000 &&
                  record.peakFatigueSeconds.isFinite && record.peakFatigueSeconds >= 0 && record.peakFatigueSeconds <= record.activeSeconds &&
                  record.breaksOffered >= 0 && record.breaksOffered <= 1_000_000 && record.breaksCompleted >= 0 && record.breaksSkipped >= 0 &&
                  record.breaksCompleted <= record.breaksOffered && record.breaksSkipped <= record.breaksOffered - record.breaksCompleted &&
                  record.hourlySeconds.count == 24 && record.hourlySeconds.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 7200 }
              }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "备份中的统计数据无效或日期重复"))
        }
        return state
    }
}
public enum CSVExporter {
    public static func render(_ records: [DailyRecord]) -> String {
        var lines = ["date,active_seconds,peak_fatigue_seconds,breaks_offered,breaks_completed,breaks_skipped,completion_rate"]
        for record in records.sorted(by: { $0.day < $1.day }) {
            let safeDay = "\"" + record.day.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let day = record.day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? record.day : safeDay
            lines.append([day, String(Int(record.activeSeconds)), String(Int(record.peakFatigueSeconds)), String(record.breaksOffered), String(record.breaksCompleted), String(record.breaksSkipped), String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), record.completionRate)].joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
