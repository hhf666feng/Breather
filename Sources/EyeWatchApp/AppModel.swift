import AppKit
import Combine
import EyeWatchCore
import ServiceManagement
import UniformTypeIdentifiers
import UserNotifications

private struct StoredBackup: Codable { var settings: MonitorSettings; var records: [DailyRecord] }

@MainActor
final class AppModel: ObservableObject {
    @Published var engine: MonitorEngine
    @Published var settings: MonitorSettings
    @Published var errorMessage: String?
    @Published var launchAtLogin = false
    private let store: LocalStore
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var activitySubscription: AnyCancellable?
    private lazy var activityMonitor = ActivityMonitor(isolated: isolated)
    @Published private(set) var activitySource: ActivitySource = .systemInput
    private var saveTicks = 0
    private(set) var persistenceWriteCount = 0
    private var systemSleeping = false
    private var displaySleeping = false
    private var sessionInactive = false
    private var screenLocked = false
    private var isSleeping: Bool { systemSleeping || displaySleeping || sessionInactive || screenLocked }
    private var canPersist = true
    private var advanceNotified = false
    private var dailyLimitNotified: String?
    private var pauseUntil: Date?
    private(set) var reminderGeneration = 0
    func isReminderCurrent(_ generation: Int) -> Bool {
        generation == reminderGeneration && !isDetectionSuspended && engine.phase == .monitoring &&
        settings.isScheduled(at: Date()) && fatigue >= settings.fatigueThreshold - 0.001
    }
    private var presenter: BreakPresenter?
    let isolated: Bool

    init(isolatedDirectory: URL? = nil, applySmokeLanguagePreset: Bool = true) {
        let args = ProcessInfo.processInfo.arguments
        isolated = isolatedDirectory != nil || args.contains("--smoke-test") || args.contains("--stability-test") || args.contains("--demo")
        let directory = isolatedDirectory ?? (isolated
            ? FileManager.default.temporaryDirectory.appendingPathComponent("EyeWatch-preview-\(ProcessInfo.processInfo.processIdentifier)")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EyeWatch", isDirectory: true))
        store = LocalStore(directory: directory)
        var loadedSettings = MonitorSettings()
        var loadedRecords: [DailyRecord] = []
        var loadError: (String, String)?
        do {
            let state = try store.load()
            loadedSettings = state.settings; loadedRecords = state.records
        } catch {
            // Preserve unreadable state before any subsequent writes.
            let original = directory.appendingPathComponent("state.json")
            let backup = directory.appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.copyItem(at: original, to: backup)
                loadError = ("本地数据读取失败，原文件已备份：\(backup.lastPathComponent)。\(error.localizedDescription)", "Local data could not be read. The original file was backed up as \(backup.lastPathComponent). \(error.localizedDescription)")
            } catch {
                canPersist = false
                loadError = ("数据读取失败，无法备份。请先备份 Application Support/EyeWatch 中的数据。\(error.localizedDescription)", "Local data could not be read or backed up. Back up the data in Application Support/EyeWatch before continuing. \(error.localizedDescription)")
            }
        }
        // This preset never changes the language of a normal launch or a persisted-state reload.
        if applySmokeLanguagePreset && args.contains("--smoke-test") && args.contains("--language-en") {
            loadedSettings.language = .english
        }
        settings = loadedSettings
        engine = MonitorEngine(settings: loadedSettings, records: loadedRecords)
        errorMessage = loadError.map { loadedSettings.language.choose($0.0, $0.1) }
        if args.contains("--demo") && isolatedDirectory == nil { configureDemo() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if !isolated, let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            // This optional session hint complements public workspace and lock notifications.
            screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
            if let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool { sessionInactive = !onConsole }
        }
        activitySubscription = activityMonitor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    var language: AppLanguage { settings.language }
    func text(_ zh: String, _ en: String) -> String { language.choose(zh, en) }
    var localizedRestMessage: String { language.restMessage(settings.restMessage) }
    var inputPermissionGranted: Bool { activityMonitor.accessibilityAuthorized }
    var screenPermissionGranted: Bool { activityMonitor.screenRecordingAuthorized }
    var inputDetectionRunning: Bool { activityMonitor.inputMonitoringRunning }
    var screenDetectionRunning: Bool { activityMonitor.screenMonitoringRunning }
    var isDetectionSuspended: Bool { isSleeping || NSScreen.screens.isEmpty || isPaused || engine.phase == .resting }
    var activityMonitorError: String? { activityMonitor.lastError }
    var detectionStatus: String {
        if isSleeping || NSScreen.screens.isEmpty { return text("屏幕锁定、休眠或会话不可用", "Screen locked, asleep, or session unavailable") }
        if isPaused { return text("监测已暂停", "Monitoring paused") }
        if engine.phase == .resting { return text("休息期间暂停活动采样", "Activity sampling paused during your break") }
        switch activitySource {
        case .systemInput: return text("系统键鼠空闲时间", "System input idle time")
        case .enhancedInput: return text("已授权的键鼠活动", "Authorized input activity")
        case .screenChanges: return text("已授权的屏幕变化", "Authorized screen changes")
        case .idle: return text("未检测到近期活动", "No recent activity detected")
        case .unavailable: return text("屏幕不可用，暂停记录", "Screen unavailable; recording paused")
        case .continuous: return text("阅读／观影模式持续计时", "Continuous reading / video mode")
        }
    }
    func requestInputPermission() { activityMonitor.requestAccessibilityPermission(); refreshDetectionPermissions() }
    func requestScreenPermission() { activityMonitor.requestScreenRecordingPermission(); refreshDetectionPermissions() }
    func openInputPermissionSettings() { activityMonitor.openAccessibilitySettings() }
    func openScreenPermissionSettings() { activityMonitor.openScreenRecordingSettings() }
    func refreshDetectionPermissions() { activityMonitor.refreshPermissions(); configureDetection() }
    private func configureDetection() {
        activityMonitor.configure(settings: settings, screenAvailable: !isDetectionSuspended)
    }
    private func activityDecision(systemIdle: Double, available: Bool) -> ActivityDecision {
        ActivityClassifier.evaluate(activityMonitor.signals(systemIdleSeconds: systemIdle), settings: settings, screenAvailable: available)
    }

    // Smoke uses an independently initialized model to prove that the on-disk language survives a restart.
    // Returning nil outside isolated storage prevents the harness from touching real user data.
    func reloadedIsolatedModel() -> AppModel? {
        guard isolated else { return nil }
        return AppModel(isolatedDirectory: store.directory, applySmokeLanguagePreset: false)
    }
    func persistedIsolatedLanguage() throws -> AppLanguage? {
        guard isolated else { return nil }
        return try LocalStore(directory: store.directory).load().settings.language
    }

    func isolatedActivityChecks() -> [String: Bool] {
        guard isolated else { return [:] }
        let originalSettings = settings, originalEngine = engine
        let originalSource = activitySource
        let previousSystemSleep = systemSleeping, previousDisplaySleep = displaySleeping
        let previousSession = sessionInactive, previousLock = screenLocked
        var checks: [String: Bool] = [:]
        settings.enhancedInputDetection = true; settings.screenActivityDetection = true
        saveSettings()
        refreshDetectionPermissions()
        checks["isolatedSensorsNotRunning"] = !inputDetectionRunning && !screenDetectionRunning
        checks["isolatedPermissionsNotPretended"] = !inputPermissionGranted && !screenPermissionGranted
        let fallback = activityDecision(systemIdle: 600, available: true)
        checks["missingPermissionFallsBackToIdle"] = fallback.source == .idle && fallback.idleSeconds >= settings.idleSeconds
        settings.monitoringMode = .continuous; engine.settings = settings
        screenLocked = true
        handleWorkspaceEvent(NSWorkspace.screensDidWakeNotification)
        checks["displayWakeDoesNotUnlockSession"] = isSleeping && activityDecision(systemIdle: 0, available: !isSleeping).source == .unavailable
        screenLocked = false; systemSleeping = true; displaySleeping = true; sessionInactive = true
        handleWorkspaceEvent(NSWorkspace.screensDidWakeNotification)
        checks["displayWakeDoesNotClearSystemSleep"] = isSleeping && systemSleeping && sessionInactive
        handleWorkspaceEvent(NSWorkspace.didWakeNotification)
        checks["systemWakeDoesNotClearInactiveSession"] = isSleeping && sessionInactive
        handleWorkspaceEvent(NSWorkspace.sessionDidBecomeActiveNotification)
        checks["availableAfterAllAbsenceReasonsClear"] = !isSleeping
        settings = originalSettings; engine = originalEngine; activitySource = originalSource
        systemSleeping = previousSystemSleep; displaySleeping = previousDisplaySleep
        sessionInactive = previousSession; screenLocked = previousLock
        configureDetection(); persist()
        return checks
    }

    var fatigue: Double { engine.fatigue }
    var records: [DailyRecord] { engine.records }
    var today: DailyRecord { records.first { $0.day == engine.dayKey(Date()) } ?? DailyRecord(day: engine.dayKey(Date())) }
    var isPaused: Bool { engine.phase == .paused }
    var phaseTitle: String {
        if isSleeping || NSScreen.screens.isEmpty { return text("屏幕不可用", "Screen unavailable") }
        switch engine.phase {
        case .monitoring: return text("监测中", "Monitoring")
        case .idle: return text("空闲恢复中", "Recovering while idle")
        case .resting: return text("休息中", "Resting")
        case .paused: return text("已暂停", "Paused")
        case .snoozed: return text("提醒已延后", "Reminder snoozed")
        case .outsideSchedule: return text("提醒时段外", "Outside reminder hours")
        }
    }
    var remainingText: String {
        let seconds: Double
        if engine.phase == .resting { seconds = engine.breakRemaining }
        else if engine.phase == .snoozed, let end = engine.snoozeEnd { seconds = max(0, end.timeIntervalSinceNow) }
        else { seconds = max(0, settings.workSeconds * settings.fatigueThreshold / 100 - engine.workElapsed) }
        return Self.clock(seconds)
    }
    static func clock(_ seconds: Double) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func start() {
        guard timer == nil else { return }
        presenter = BreakPresenter(model: self)
        configureDetection()
        let initial = activityDecision(systemIdle: SystemInputIdle.read(), available: !isSleeping && !NSScreen.screens.isEmpty)
        activitySource = initial.source
        engine.tick(at: Date(), idleSeconds: initial.idleSeconds, screenAvailable: initial.screenAvailable)
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in self?.handleWorkspaceEvent(notification.name) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for name in [Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked")] {
            distributedObservers.append(distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self else { return }
                    self.screenLocked = notification.name.rawValue == "com.apple.screenIsLocked"
                    self.availabilityDidChange()
                }
            })
        }
        appObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDetectionPermissions() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isSleeping else { return }
                self.advance(idle: SystemInputIdle.read())
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func handleWorkspaceEvent(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification: systemSleeping = true
        case NSWorkspace.didWakeNotification: systemSleeping = false
        case NSWorkspace.screensDidSleepNotification: displaySleeping = true
        case NSWorkspace.screensDidWakeNotification: displaySleeping = false
        case NSWorkspace.sessionDidResignActiveNotification: sessionInactive = true
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionInactive = false
        default: return
        }
        availabilityDidChange()
    }
    private func availabilityDidChange() {
        configureDetection()
        if isSleeping {
            activitySource = .unavailable
            persist()
        } else {
            // Exclude the entire absence, including a short lock in continuous mode.
            advance(idle: 600, screenAvailable: false)
        }
    }
    private func advance(idle: Double, screenAvailable: Bool = true) {
        let now = Date()
        if let end = pauseUntil, now >= end { pauseUntil = nil; engine.setPaused(false, at: now) }
        let previous = engine.phase
        let oldNotifications = engine.notificationCount
        let completed = records.reduce(0) { $0 + $1.breaksCompleted }
        configureDetection()
        let decision = activityDecision(systemIdle: idle, available: screenAvailable && !isSleeping && !NSScreen.screens.isEmpty)
        activitySource = decision.source
        engine.tick(at: now, idleSeconds: decision.idleSeconds, screenAvailable: decision.screenAvailable)
        syncPresentation(previous: previous)
        if records.reduce(0, { $0 + $1.breaksCompleted }) > completed, settings.soundEnabled, !isolated { NSSound(named: "Glass")?.play() }
        if engine.notificationCount > oldNotifications { presenter?.notifyRest() }
        let remaining = max(0, settings.workSeconds * settings.fatigueThreshold / 100 - engine.workElapsed)
        if remaining > 60 { advanceNotified = false }
        if settings.advanceNoticeEnabled, engine.phase == .monitoring, remaining > 0, remaining <= 60, !advanceNotified {
            advanceNotified = true
            presenter?.notify(title: text("还有 1 分钟，准备休息", "Your break starts in 1 minute"), body: text("给手头的事情收个尾，马上让眼睛放松一下。", "Finish what you are doing and get ready to rest your eyes."))
        }
        if settings.dailyLimitEnabled, today.activeSeconds >= settings.dailyLimitHours * 3600, dailyLimitNotified != today.day {
            dailyLimitNotified = today.day
            presenter?.notify(title: text("今日用眼已达到目标上限", "You have reached today's screen time limit"), body: text("今天已使用电脑 \(language.duration(settings.dailyLimitHours * 3600))，记得减少连续用眼。", "You have used your computer for \(language.duration(settings.dailyLimitHours * 3600)) today. Take regular breaks from the screen."))
        }
        saveTicks += 1
        if saveTicks >= 30 { saveTicks = 0; persist() }
        refreshDockBadge()
    }
    func refreshDockBadge() {
        guard settings.showDockIcon else { NSApp.dockTile.badgeLabel = nil; return }
        NSApp.dockTile.badgeLabel = engine.phase == .resting ? text("休息", "Rest") : (fatigue >= 80 ? "\(Int(fatigue))%" : nil)
    }
    private func syncPresentation(previous: MonitorPhase) {
        configureDetection()
        if engine.phase == .resting && previous != .resting { presenter?.show() }
        if engine.phase != .resting && previous == .resting { presenter?.dismiss(); persist() }
    }
    func pauseResume() {
        guard authorizeSkip() else { return }
        reminderGeneration += 1
        pauseUntil = nil
        let previous = engine.phase
        engine.setPaused(!isPaused, at: Date())
        syncPresentation(previous: previous); persist()
    }
    func takeBreak() {
        reminderGeneration += 1
        pauseUntil = nil
        let previous = engine.phase
        engine.startBreak(at: Date())
        syncPresentation(previous: previous); persist()
    }
    func pause(for seconds: Double) {
        guard engine.phase != .resting else { return }
        reminderGeneration += 1
        engine.setPaused(true, at: Date()); pauseUntil = Date().addingTimeInterval(seconds); configureDetection(); persist()
    }
    private func authorizeSkip() -> Bool {
        guard engine.phase == .resting else { return true }
        guard !engine.breakIsStrict else { return false }
        guard settings.skipChallengeEnabled else { return true }
        let left = Int.random(in: 12...49), right = Int.random(in: 12...49)
        let alert = NSAlert(); alert.messageText = text("先算一算，再决定是否跳过", "Solve this before skipping your break")
        alert.informativeText = "\(left) + \(right) = ?"
        alert.addButton(withTitle: text("确认跳过", "Skip break")); alert.addButton(withTitle: text("继续休息", "Keep resting"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 25))
        field.placeholderString = text("输入答案", "Enter your answer"); alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) == left + right else {
            errorMessage = text("答案不正确，继续让眼睛休息一下吧。", "That answer is incorrect. Give your eyes a little more rest."); return false
        }
        return true
    }
    func skipBreak() {
        guard authorizeSkip() else { return }
        reminderGeneration += 1
        let previous = engine.phase
        if engine.skipBreak(at: Date()) { syncPresentation(previous: previous); persist() }
    }
    func snooze() {
        guard authorizeSkip() else { return }
        reminderGeneration += 1
        let previous = engine.phase
        engine.snooze(until: Date().addingTimeInterval(300))
        syncPresentation(previous: previous); persist()
    }
    func saveSettings() {
        settings = settings.validated()
        engine.settings = settings
        configureDetection()
        activitySource = activityDecision(systemIdle: SystemInputIdle.read(), available: !isSleeping && !NSScreen.screens.isEmpty).source
        persist()
        if (settings.reminderStyle == .notification || settings.advanceNoticeEnabled || settings.dailyLimitEnabled) && !isolated {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error { Task { @MainActor in self.errorMessage = self.text("通知权限请求失败：\(error.localizedDescription)", "Could not request notification permission: \(error.localizedDescription)") } }
            }
        }
    }
    func persist() {
        guard canPersist else { return }
        do {
            try store.save(settings: settings, records: engine.records)
            persistenceWriteCount += 1
            if let path = settings.backupDirectory, !isolated {
                let backup = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("EyeWatch-backup.json")
                let data = try Data(contentsOf: store.directory.appendingPathComponent("state.json"))
                try data.write(to: backup, options: .atomic)
            }
        } catch { errorMessage = text("保存或自动备份失败：\(error.localizedDescription)", "Could not save data or update the automatic backup: \(error.localizedDescription)") }
    }
    func chooseBackupDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.title = text("自动备份位置", "Automatic backup location")
        panel.prompt = text("选择文件夹", "Choose folder")
        panel.message = text("选择自动备份文件夹，也可选择 iCloud Drive 中的文件夹。备份每 30 秒更新。", "Choose a folder for automatic backups, including a folder in iCloud Drive. Backups update every 30 seconds.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.backupDirectory = url.path; saveSettings()
    }
    func exportBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Breather-backup.json"
        panel.title = text("导出歇会儿备份", "Export Breather backup")
        panel.prompt = text("导出", "Export")
        panel.message = text("导出偏好设置和用眼记录。", "Export your preferences and screen time records.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(StoredBackup(settings: settings, records: records)).write(to: url, options: .atomic) }
        catch { errorMessage = text("导出备份失败：\(error.localizedDescription)", "Could not export the backup: \(error.localizedDescription)") }
    }
    func restoreBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.title = text("恢复歇会儿备份", "Restore Breather backup")
        panel.prompt = text("恢复", "Restore")
        panel.message = text("选择歇会儿备份（兼容旧版 EyeWatch）。当前记录会先保存为恢复前备份。", "Choose a Breather backup. Older EyeWatch backups are also supported. Your current records will be backed up before restoring.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let restored = try LocalStore.decode(Data(contentsOf: url))
            guard engine.phase != .resting else { errorMessage = text("请先完成当前休息，再恢复备份。", "Finish your current break before restoring a backup."); return }
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let safety = store.directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try JSONEncoder().encode(StoredBackup(settings: settings, records: records)).write(to: safety, options: .atomic)
            var imported = restored.settings
            imported.backupDirectory = nil
            if let path = imported.wallpaperPath, !FileManager.default.fileExists(atPath: path) { imported.wallpaperPath = nil }
            // Commit to disk before replacing the visible state; failed writes leave the session intact.
            try store.save(settings: imported, records: restored.records)
            reminderGeneration += 1; pauseUntil = nil; advanceNotified = false; dailyLimitNotified = nil
            settings = imported; engine = MonitorEngine(settings: imported, records: restored.records)
            engine.resetClock(at: Date()); canPersist = true; errorMessage = nil
            configureDetection()
        } catch { errorMessage = text("恢复失败，现有数据未更改：\(error.localizedDescription)", "Restore failed. Your existing data has not changed: \(error.localizedDescription)") }
    }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Breather-\(engine.dayKey(Date())).csv"
        panel.title = text("导出用眼记录", "Export screen time records")
        panel.prompt = text("导出", "Export")
        panel.message = text("将全部用眼记录导出为 CSV 文件。", "Export all screen time records as a CSV file.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try CSVExporter.render(records).write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = text("导出失败：\(error.localizedDescription)", "Could not export the records: \(error.localizedDescription)") }
    }
    func chooseWallpaper() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]; panel.canChooseDirectories = false
        panel.title = text("休息背景", "Break background")
        panel.prompt = text("使用图片", "Use image")
        panel.message = text("选择一张用于休息窗口的背景图片。", "Choose a background image for your break window.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard NSImage(contentsOf: url) != nil else { errorMessage = text("无法读取这张图片，请选择有效的图片。", "This image could not be read. Choose a valid image file."); return }
        do {
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let target = store.directory.appendingPathComponent("wallpaper-\(UUID().uuidString).\(url.pathExtension)")
            try FileManager.default.copyItem(at: url, to: target)
            settings.wallpaperPath = target.path
            saveSettings()
        } catch { errorMessage = text("导入背景失败：\(error.localizedDescription)", "Could not import the background: \(error.localizedDescription)") }
    }
    func clearWallpaper() { settings.wallpaperPath = nil; saveSettings() }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { errorMessage = text("请在系统设置 → 通用 → 登录项中允许歇会儿。", "Allow Breather in System Settings → General → Login Items.") }
        } catch { launchAtLogin = SMAppService.mainApp.status == .enabled; errorMessage = text("无法修改登录项：\(error.localizedDescription)", "Could not change the login item: \(error.localizedDescription)") }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        activityMonitor.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(); distributedObservers.removeAll(); appObservers.removeAll()
        presenter?.dismiss(); persist()
    }

    private func configureDemo() {
        let calendar = Calendar.current
        var samples: [DailyRecord] = []
        let keyEngine = MonitorEngine()
        for offset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            var record = DailyRecord(day: keyEngine.dayKey(date))
            record.activeSeconds = Double([13800, 16200, 11000, 19200, 14400, 15600, 8520][6 - offset])
            record.peakFatigueSeconds = Double(180 + offset * 60)
            record.breaksOffered = 12; record.breaksCompleted = 10; record.breaksSkipped = 2
            for hour in 8...17 { record.hourlySeconds[hour] = record.activeSeconds / 10 * (hour % 2 == 0 ? 1.25 : 0.75) }
            samples.append(record)
        }
        engine = MonitorEngine(settings: settings, records: samples)
        let now = Date()
        engine.tick(at: now.addingTimeInterval(-720), idleSeconds: 0)
        for step in 1...720 { engine.tick(at: now.addingTimeInterval(Double(step - 720)), idleSeconds: 0) }
    }
}
