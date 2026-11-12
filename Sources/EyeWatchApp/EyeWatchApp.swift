import AppKit
import SwiftUI
import Combine
import EyeWatchCore

@main
enum EyeWatchApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Load the saved preference before opting into the Dock.
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var subscription: AnyCancellable?
    private var appliedLanguage: AppLanguage?
    private var dockVisibility = DockVisibilityCoordinator()
    private var dockPolicyFailureMessage: String?
    private var dockPolicyAttempts = 0
    private var forcedDockPolicyFailure = false
    private var statusUpdateCount = 0
    private var statusUpdateQueued = false
    private var stabilityHeartbeat: Timer?
    private var smokeDockChecks: [String: Bool] = [:]
    private var smokeActivityChecks: [String: Bool] = [:]
    private var smokeShortcutChecks: [String: Bool] = [:]
    private var smokeLanguageChecks: [String: Bool] = [:]
    private var smokeRestWindowNumbers: Set<Int> = []
    private var smokeEditMenuIdentity: ObjectIdentifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let args = ProcessInfo.processInfo.arguments
        let initialWidth: CGFloat = model.isolated && args.contains("--smoke-compact") ? 1000 : 1180
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("mujian.main")
        window.title = model.text("歇会儿 · 用眼与休息", "Breather · Screen time and breaks")
        window.minSize = NSSize(width: 1000, height: 760)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LanguageRoot(model: model) { ContentView(model: model) })
        window.center()
        let usableHeight = NSScreen.main?.visibleFrame.height ?? 900
        if window.frame.height > usableHeight { window.setContentSize(NSSize(width: initialWidth, height: max(720, usableHeight - 45))) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusMark()
        let statusMenu = NSMenu(); statusMenu.delegate = self; statusItem.menu = statusMenu
        subscription = model.objectWillChange.sink { [weak self] in
            guard let self, !self.statusUpdateQueued else { return }
            // Coalesce publications and read @Published state on the next main-loop turn.
            self.statusUpdateQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.statusUpdateQueued = false
                self.updateStatus()
            }
        }
        model.start(); updateStatus(); showWindow()
        if let index = args.firstIndex(of: "--stability-test"), args.count > index + 1, model.isolated {
            runStabilityTest(output: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            return
        }
        if let i = args.firstIndex(of: "--smoke-test"), args.count > i + 1 {
            let output = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.smokeTest(output: output) }
        }
    }
    private func rebuildMainMenu() {
        let text = model.text
        let brand = text("歇会儿", "Breather")
        let labels = [
            "mujian.app.about": text("关于歇会儿", "About Breather"),
            "mujian.app.preferences": text("偏好设置…", "Preferences…"),
            "mujian.file.close": text("关闭窗口", "Close Window"),
            "mujian.window.minimize": text("最小化", "Minimize"),
            "mujian.window.zoom": text("缩放", "Zoom"),
            "mujian.edit.redo": text("重做", "Redo"),
            "mujian.app.show": text("显示主窗口", "Show main window"),
            "mujian.app.rest": text("现在休息", "Take a break now"),
            "mujian.app.hide": text("隐藏歇会儿", "Hide Breather"),
            "mujian.app.quit": text("退出歇会儿", "Quit Breather"),
            "mujian.edit.undo": text("撤销", "Undo"),
            "mujian.edit.cut": text("剪切", "Cut"),
            "mujian.edit.copy": text("复制", "Copy"),
            "mujian.edit.paste": text("粘贴", "Paste"),
            "mujian.edit.select-all": text("全选", "Select all")
        ]
        if let existing = NSApp.mainMenu,
           let appRoot = existing.items.first(where: { $0.identifier?.rawValue == "mujian.app-menu" }),
           let editRoot = existing.items.first(where: { $0.identifier?.rawValue == "mujian.edit-menu" }) {
            // Preserve native menus so AppKit does not re-insert its Dictation/Emoji items on every switch.
            appRoot.title = brand; appRoot.submenu?.title = brand
            editRoot.title = text("编辑", "Edit"); editRoot.submenu?.title = editRoot.title
            for root in existing.items {
                if root.identifier?.rawValue == "mujian.file-menu" { root.title = text("文件", "File"); root.submenu?.title = root.title }
                if root.identifier?.rawValue == "mujian.window-menu" { root.title = text("窗口", "Window"); root.submenu?.title = root.title }
                for item in root.submenu?.items ?? [] {
                    if let id = item.identifier?.rawValue, let label = labels[id] { item.title = label }
                }
            }
            return
        }
        let menu = NSMenu()
        let appRoot = NSMenuItem(title: brand, action: nil, keyEquivalent: "")
        appRoot.identifier = NSUserInterfaceItemIdentifier("mujian.app-menu")
        let appMenu = NSMenu(title: brand)
        let about = NSMenuItem(title: text("关于歇会儿", "About Breather"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self; appMenu.addItem(about)
        let preferences = NSMenuItem(title: text("偏好设置…", "Preferences…"), action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self; appMenu.addItem(preferences)
        appMenu.addItem(.separator())
        let show = NSMenuItem(title: text("显示主窗口", "Show main window"), action: #selector(showWindow), keyEquivalent: "0")
        show.target = self; appMenu.addItem(show)
        let restItem = NSMenuItem(title: text("现在休息", "Take a break now"), action: #selector(takeBreak), keyEquivalent: "r")
        restItem.keyEquivalentModifierMask = [.command, .shift]; restItem.target = self; appMenu.addItem(restItem)
        let hide = NSMenuItem(title: text("隐藏歇会儿", "Hide Breather"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp; appMenu.addItem(hide)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: text("退出歇会儿", "Quit Breather"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; appMenu.addItem(quit)
        for (item, id) in [(about, "about"), (preferences, "preferences"), (show, "show"), (restItem, "rest"), (hide, "hide"), (quit, "quit")] {
            item.identifier = NSUserInterfaceItemIdentifier("mujian.app.\(id)")
        }
        appRoot.submenu = appMenu; menu.addItem(appRoot)
        let fileRoot = NSMenuItem(title: text("文件", "File"), action: nil, keyEquivalent: "")
        fileRoot.identifier = NSUserInterfaceItemIdentifier("mujian.file-menu")
        let fileMenu = NSMenu(title: fileRoot.title)
        let close = NSMenuItem(title: text("关闭窗口", "Close Window"), action: #selector(closeFocusedWindow), keyEquivalent: "w")
        close.target = self
        close.identifier = NSUserInterfaceItemIdentifier("mujian.file.close")
        fileMenu.addItem(close); fileRoot.submenu = fileMenu; menu.addItem(fileRoot)
        let editRoot = NSMenuItem(title: text("编辑", "Edit"), action: nil, keyEquivalent: "")
        editRoot.identifier = NSUserInterfaceItemIdentifier("mujian.edit-menu")
        let edit = NSMenu(title: text("编辑", "Edit"))
        edit.addItem(withTitle: text("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: text("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(withTitle: text("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: text("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: text("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: text("全选", "Select all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for (item, id) in zip(edit.items, ["undo", "redo", "cut", "copy", "paste", "select-all"]) {
            item.identifier = NSUserInterfaceItemIdentifier("mujian.edit.\(id)")
        }
        editRoot.submenu = edit; menu.addItem(editRoot)
        let windowRoot = NSMenuItem(title: text("窗口", "Window"), action: nil, keyEquivalent: "")
        windowRoot.identifier = NSUserInterfaceItemIdentifier("mujian.window-menu")
        let windowMenu = NSMenu(title: windowRoot.title)
        let minimize = NSMenuItem(title: text("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimize.identifier = NSUserInterfaceItemIdentifier("mujian.window.minimize"); windowMenu.addItem(minimize)
        let zoom = NSMenuItem(title: text("缩放", "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        zoom.identifier = NSUserInterfaceItemIdentifier("mujian.window.zoom"); windowMenu.addItem(zoom)
        windowRoot.submenu = windowMenu; menu.addItem(windowRoot)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
    private func updateLanguageIfNeeded() {
        guard appliedLanguage != model.language else { return }
        appliedLanguage = model.language
        rebuildMainMenu()
        window.title = model.text("歇会儿 · 用眼与休息", "Breather · Screen time and breaks")
        if let menu = statusItem.menu { menuNeedsUpdate(menu) }
        model.refreshDockBadge()
    }
    @objc func showWindow() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func closeFocusedWindow() {
        // Menu actions may arrive before AppKit has assigned a key window after activation.
        // Prefer the active rest panel so closing never bypasses its skip/strict policy.
        let focused = NSApp.keyWindow ?? visibleRestWindows.first ?? NSApp.mainWindow ?? (window.isVisible ? window : nil)
        focused?.performClose(nil)
    }
    @objc private func showPreferences() {
        showWindow()
        NotificationCenter.default.post(name: Notification.Name("EyeWatch.navigate"), object: "提醒设置")
        NotificationCenter.default.post(name: Notification.Name("EyeWatch.scroll"), object: "top")
    }
    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: model.text("歇会儿", "Breather"),
            .applicationVersion: version,
            .credits: NSAttributedString(string: model.text("本地用眼监测与休息提醒\n基于公开功能及 REA 本地分析独立实现。", "Local screen time monitoring and break reminders\nIndependently implemented from public features and local REA analysis."))
        ])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    private func statusMark() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            let scale: CGFloat = 18 / 576
            let point: (CGFloat, CGFloat) -> NSPoint = { x, y in NSPoint(x: (x-224)*scale, y: (y-224)*scale) }
            let path = NSBezierPath(); path.windingRule = .evenOdd
            path.move(to: point(256,256)); path.line(to: point(768,256)); path.line(to: point(768,544))
            path.line(to: point(704,544)); path.line(to: point(704,320)); path.line(to: point(544,320))
            path.line(to: point(544,704)); path.line(to: point(576,704)); path.line(to: point(576,768)); path.line(to: point(256,768)); path.close()
            for (y, height) in [(320.0,80.0), (448.0,128.0), (624.0,80.0)] {
                path.appendRect(NSRect(x: (320-224)*scale, y: (y-224)*scale, width: 160*scale, height: height*scale))
            }
            path.fill()
            NSBezierPath(rect: NSRect(x: (640-224)*scale, y: (704-224)*scale, width: 128*scale, height: 64*scale)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
    private func updateDockVisibilityIfNeeded() {
        let visible = model.settings.showDockIcon
        let keepFocus = window.isVisible && window.isKeyWindow
        var rejected = false
        let forced = forcedDockPolicyFailure && model.isolated
        let changed = dockVisibility.apply(requested: visible, current: NSApp.activationPolicy() == .regular) { requested in
            dockPolicyAttempts += 1
            let accepted = forced ? false : NSApp.setActivationPolicy(requested ? .regular : .accessory)
            rejected = !accepted
            return accepted
        }
        if rejected {
            // Never mutate/persist settings from a failed rendering/OS-status update.
            let message = model.text("暂时无法更改程序坞显示状态，可重新切换开关重试；应用仍在菜单栏运行", "Dock visibility could not be changed. Toggle the preference to retry; the menu bar remains available")
            if dockPolicyFailureMessage != message {
                dockPolicyFailureMessage = message
                model.errorMessage = message
            }
        }
        guard changed else { return }
        dockPolicyFailureMessage = nil
        appliedLanguage = nil
        model.refreshDockBadge()
        if keepFocus {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window.isVisible else { return }
                self.showWindow()
            }
        }
    }
    private var updatingStatus = false
    private func updateStatus() {
        guard let model, !updatingStatus else { return }
        updatingStatus = true
        statusUpdateCount += 1
        defer { updatingStatus = false }
        updateDockVisibilityIfNeeded()
        updateLanguageIfNeeded()
        statusItem.button?.title = model.settings.showMenuBarTime ? " \(Int(model.fatigue))% · \(model.remainingText)" : " \(Int(model.fatigue))%"
        statusItem.button?.toolTip = model.phaseTitle
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = NSMenuItem(title: "\(model.phaseTitle) · \(Int(model.fatigue))%", action: nil, keyEquivalent: "")
        state.isEnabled = false; menu.addItem(state)
        menu.addItem(.separator())
        addItem(menu, model.text("显示歇会儿", "Show Breather"), #selector(showWindow))
        addItem(menu, model.text("现在休息", "Take a break now"), #selector(takeBreak))
        if model.engine.phase == .resting {
            if !model.engine.breakIsStrict { addItem(menu, model.text("跳过这次休息", "Skip this break"), #selector(skipBreak)) }
        } else {
            addItem(menu, model.isPaused ? model.text("继续监测", "Resume monitoring") : model.text("暂停监测", "Pause monitoring"), #selector(pauseResume))
            if !model.isPaused {
                addItem(menu, model.text("暂停 30 分钟", "Pause for 30 minutes"), #selector(pauseThirty))
                addItem(menu, model.text("暂停 1 小时", "Pause for 1 hour"), #selector(pauseHour))
                addItem(menu, model.text("暂停至明天", "Pause until tomorrow"), #selector(pauseTomorrow))
            }
        }
        if !model.isPaused && !(model.engine.phase == .resting && model.engine.breakIsStrict) { addItem(menu, model.text("延后提醒 5 分钟", "Snooze reminders for 5 minutes"), #selector(snooze)) }
        menu.addItem(.separator())
        addItem(menu, model.text("导出全部数据 CSV…", "Export all data as CSV…"), #selector(exportCSV))
        addItem(menu, model.text("退出歇会儿", "Quit Breather"), #selector(quit))
    }
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    @objc private func takeBreak() { model.takeBreak() }
    @objc private func skipBreak() { model.skipBreak() }
    @objc private func pauseResume() { model.pauseResume() }
    @objc private func pauseThirty() { model.pause(for: 1800) }
    @objc private func pauseHour() { model.pause(for: 3600) }
    @objc private func pauseTomorrow() {
        let midnight = Calendar.current.startOfDay(for: Date())
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: midnight) { model.pause(for: tomorrow.timeIntervalSinceNow) }
    }
    @objc private func snooze() { model.snooze() }
    @objc private func exportCSV() { model.exportCSV() }
    @objc private func quit() { NSApp.terminate(nil) }

    private var visibleRestWindows: [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "mujian.rest" && $0.isVisible }
    }
    private func capture(_ name: String, directory: URL, source: NSView? = nil) throws {
        guard let view = source ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "mujian.main" })?.contentView else { throw CocoaError(.fileWriteUnknown) }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name))
    }
    private func smokeTest(output: URL) {
        guard model.isolated else { smokeFailure(CocoaError(.fileWriteNoPermission)); return }
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { smokeFailure(error); return }
        let args = ProcessInfo.processInfo.arguments
        smokeLanguageChecks["englishPresetApplied"] = !args.contains("--language-en") || model.language == .english
        smokeActivityChecks = model.isolatedActivityChecks()
        smokeRejectedDockTransition { self.captureScene(0, output: output) }
    }
    private func runStabilityTest(output: URL) {
        guard model.isolated else { return }
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { smokeFailure(error); return }
        smokeRejectedDockTransition {
            self.model.engine.setPaused(true, at: Date())
            self.forcedDockPolicyFailure = true
            self.dockVisibility = DockVisibilityCoordinator()
            self.model.settings.showDockIcon = !(NSApp.activationPolicy() == .regular)
            self.model.saveSettings()
            self.updateStatus()
            let initialAttempts = self.dockPolicyAttempts
            let initialWrites = self.model.persistenceWriteCount
            let initialUpdates = self.statusUpdateCount
            let started = Date()
            var samples = 0
            self.stabilityHeartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    samples += 1
                    let report: [String: Any] = ["elapsedSeconds": Date().timeIntervalSince(started), "heartbeats": samples,
                        "dockAttemptsAfterRejection": self.dockPolicyAttempts - initialAttempts,
                        "stateWrites": self.model.persistenceWriteCount - initialWrites,
                        "statusUpdates": self.statusUpdateCount - initialUpdates,
                        "windowVisible": self.window.isVisible, "menuBarVisible": self.statusItem.isVisible,
                        "failureChecks": self.dockRejectionChecks,
                        "passed": samples >= 120 && self.dockPolicyAttempts == initialAttempts && self.model.persistenceWriteCount - initialWrites < 12 && self.statusUpdateCount - initialUpdates < samples * 12]
                    do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("stability.json"), options: .atomic) }
                    catch { self.smokeFailure(error) }
                    if samples >= 120 { self.stabilityHeartbeat?.invalidate(); self.model.stop(); NSApp.terminate(nil) }
                }
            }
        }
    }
    private var dockRejectionChecks: [String: Bool] = [:]
    private func smokeRejectedDockTransition(completion: @escaping () -> Void) {
        guard model.isolated else { completion(); return }
        let original = model.settings.showDockIcon
        model.engine.setPaused(true, at: Date())
        let recordSnapshot = model.records
        let attemptsBefore = dockPolicyAttempts
        let updatesBefore = statusUpdateCount
        forcedDockPolicyFailure = true
        dockVisibility = DockVisibilityCoordinator()
        model.settings.showDockIcon = !(NSApp.activationPolicy() == .regular)
        let rejectedRequest = model.settings.showDockIcon
        model.saveSettings()
        let writesBefore = model.persistenceWriteCount
        // The main-loop heartbeat must run even after an OS failure and a burst of status work.
        for _ in 0..<100 { updateStatus() }
        let directUpdatesDidNotWrite = model.persistenceWriteCount == writesBefore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.dockRejectionChecks["oneAttemptOnPersistentRejection"] = self.dockPolicyAttempts == attemptsBefore + 1
            self.dockRejectionChecks["requestPreserved"] = self.model.settings.showDockIcon == rejectedRequest
            self.dockRejectionChecks["stateNotRewrittenByStatus"] = directUpdatesDidNotWrite && self.model.persistenceWriteCount - writesBefore < 3
            self.dockRejectionChecks["recordsPreserved"] = self.model.records == recordSnapshot
            self.dockRejectionChecks["mainLoopResponsive"] = self.statusUpdateCount - updatesBefore < 150
            self.dockRejectionChecks["menuBarRetained"] = self.statusItem.isVisible
            self.forcedDockPolicyFailure = false
            self.dockVisibility = DockVisibilityCoordinator()
            self.model.settings.showDockIcon = original
            self.model.engine.setPaused(false, at: Date())
            self.model.errorMessage = nil
            self.model.saveSettings()
            self.updateStatus()
            completion()
        }
    }
    private func captureScene(_ index: Int, output: URL) {
        // Navigation keys are stable identifiers shared with EyePage, independent of display language.
        let scenes: [(page: String, file: String, scroll: String, dark: Bool)] = [
            ("总览", "dashboard.png", "top", false),
            ("数据趋势", "trends.png", "top", false),
            ("数据趋势", "trends-detail.png", "bottom", false),
            ("提醒设置", "settings.png", "top", false),
            ("提醒设置", "settings-backup.png", "bottom", false),
            ("提醒设置", "settings-language.png", "language", false),
            ("提醒设置", "settings-detection.png", "detection", false),
            ("总览", "dashboard-dark.png", "top", true)
        ]
        guard index < scenes.count else {
            smokeStandardShortcuts {
                self.smokeDockVisibility { self.smokeActions(output: output) }
            }
            return
        }
        let scene = scenes[index]
        model.settings.theme = scene.dark ? .dark : .light
        NotificationCenter.default.post(name: Notification.Name("EyeWatch.navigate"), object: scene.page)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: Notification.Name("EyeWatch.scroll"), object: scene.scroll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do { try self.capture(scene.file, directory: output); self.captureScene(index + 1, output: output) }
            catch { self.smokeFailure(error) }
        }
    }
    private func performShortcut(_ key: String, modifiers: NSEvent.ModifierFlags = [.command]) -> Bool {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0) else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }
    private func smokeStandardShortcuts(completion: @escaping () -> Void) {
        showWindow()
        NSApp.mainMenu?.update()
        let statusIdentity = ObjectIdentifier(statusItem)
        smokeShortcutChecks["closeKeyEquivalent"] = performShortcut("w")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.smokeShortcutChecks["mainClosedWithoutExit"] = !self.window.isVisible && ObjectIdentifier(self.statusItem) == statusIdentity && self.statusItem.isVisible
            self.smokeShortcutChecks["showKeyEquivalent"] = self.performShortcut("0")
            self.smokeShortcutChecks["mainReopened"] = self.window.isVisible
            var settingsNavigationObserved = false
            let navigationObserver = NotificationCenter.default.addObserver(forName: Notification.Name("EyeWatch.navigate"), object: nil, queue: .main) { note in
                if (note.object as? String) == "提醒设置" { settingsNavigationObserved = true }
            }
            self.smokeShortcutChecks["preferencesKeyEquivalent"] = self.performShortcut(",")
            self.smokeShortcutChecks["preferencesNavigationObserved"] = settingsNavigationObserved
            NotificationCenter.default.removeObserver(navigationObserver)
            let windowMenu = NSApp.mainMenu?.items.first { $0.identifier?.rawValue == "mujian.window-menu" }?.submenu
            self.smokeShortcutChecks["minimizeRegistered"] = windowMenu?.items.contains { $0.keyEquivalent == "m" && $0.action == #selector(NSWindow.performMiniaturize(_:)) } == true
            self.smokeShortcutChecks["redoRegistered"] = NSApp.mainMenu?.items.first { $0.identifier?.rawValue == "mujian.edit-menu" }?.submenu?.items.contains { $0.keyEquivalent == "z" && $0.keyEquivalentModifierMask == [.command, .shift] && $0.action == Selector(("redo:")) } == true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: Notification.Name("EyeWatch.navigate"), object: "总览")
                completion()
            }
        }
    }
    private func smokeDockVisibility(completion: @escaping () -> Void) {
        let original = model.settings.showDockIcon
        let statusIdentity = ObjectIdentifier(statusItem)
        model.settings.showDockIcon = false
        model.saveSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.smokeDockChecks["accessoryPolicy"] = NSApp.activationPolicy() == .accessory
            self.smokeDockChecks["statusItemRetained"] = ObjectIdentifier(self.statusItem) == statusIdentity && self.statusItem.isVisible
            self.smokeDockChecks["hiddenPreferenceReloaded"] = self.model.reloadedIsolatedModel()?.settings.showDockIcon == false
            self.window.orderOut(nil)
            if let menu = self.statusItem.menu {
                self.menuNeedsUpdate(menu)
                if let show = menu.items.first(where: { $0.action == #selector(self.showWindow) }), let action = show.action {
                    self.smokeDockChecks["showWindowActionAvailable"] = NSApp.sendAction(action, to: show.target, from: show)
                }
                self.smokeDockChecks["quitActionAvailable"] = menu.items.contains { $0.action == #selector(self.quit) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.smokeDockChecks["windowOpenedWhileHidden"] = self.window.isVisible && NSApp.activationPolicy() == .accessory
                self.model.settings.showDockIcon = true
                self.model.saveSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.smokeDockChecks["regularPolicyRestored"] = NSApp.activationPolicy() == .regular
                    self.smokeDockChecks["visiblePreferenceReloaded"] = self.model.reloadedIsolatedModel()?.settings.showDockIcon == true
                    self.smokeDockChecks["sameStatusItemAfterRestore"] = ObjectIdentifier(self.statusItem) == statusIdentity && self.statusItem.isVisible
                    self.model.settings.showDockIcon = original
                    self.model.saveSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.smokeDockChecks["originalPreferenceRestored"] = NSApp.activationPolicy() == (original ? .regular : .accessory)
                        completion()
                    }
                }
            }
        }
    }
    private func smokeLanguageSteps(_ languages: [AppLanguage], index: Int = 0, output: URL, completion: @escaping () -> Void) {
        guard index < languages.count else { completion(); return }
        let language = languages[index]
        let rawMessage = model.settings.restMessage
        model.settings.language = language
        model.saveSettings()
        // Let the real Combine observers update native menus, window titles and SwiftUI content.
        // The harness does not invoke the refresh methods itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let prefix = language == .chinese ? "chinese" : "english"
            let choose = language.choose
            let appRoot = NSApp.mainMenu?.items.first
            let appTitles = appRoot?.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            let expectedTitles = [choose("关于歇会儿", "About Breather"), choose("偏好设置…", "Preferences…"), choose("显示主窗口", "Show main window"), choose("现在休息", "Take a break now"), choose("隐藏歇会儿", "Hide Breather"), choose("退出歇会儿", "Quit Breather")]
            self.smokeLanguageChecks["\(prefix)MainMenu"] = appRoot?.title == choose("歇会儿", "Breather") && appTitles == expectedTitles
            let editRoot = NSApp.mainMenu?.items.first { $0.identifier?.rawValue == "mujian.edit-menu" }
            let ownedEditItems = editRoot?.submenu?.items.filter { $0.identifier?.rawValue.hasPrefix("mujian.edit.") == true } ?? []
            let editTitles = ownedEditItems.map(\.title)
            self.smokeLanguageChecks["\(prefix)EditMenu"] = editRoot?.title == choose("编辑", "Edit") && editTitles == [choose("撤销", "Undo"), choose("重做", "Redo"), choose("剪切", "Cut"), choose("复制", "Copy"), choose("粘贴", "Paste"), choose("全选", "Select all")]
            if let edit = editRoot?.submenu {
                let identity = ObjectIdentifier(edit)
                if self.smokeEditMenuIdentity == nil { self.smokeEditMenuIdentity = identity }
                self.smokeLanguageChecks["\(prefix)EditMenuIdentity"] = self.smokeEditMenuIdentity == identity
            }
            if self.smokeLanguageChecks["\(prefix)EditMenu"] == false {
                print("Edit menu diagnostic [\(prefix)]: root=\(editRoot?.title ?? "nil"), items=\(editTitles)")
            }
            let statusTitles = self.statusItem.menu?.items.map(\.title) ?? []
            self.smokeLanguageChecks["\(prefix)StatusMenu"] = statusTitles.contains(choose("显示歇会儿", "Show Breather")) && statusTitles.contains(choose("退出歇会儿", "Quit Breather")) && !statusTitles.contains(choose("Quit Breather", "退出歇会儿"))
            self.smokeLanguageChecks["\(prefix)MainWindow"] = self.window.identifier?.rawValue == "mujian.main" && self.window.title == choose("歇会儿 · 用眼与休息", "Breather · Screen time and breaks")
            let rests = self.visibleRestWindows
            self.smokeLanguageChecks["\(prefix)RestWindow"] = !rests.isEmpty && rests.allSatisfy { $0.title == choose("歇会儿 · 休息时间", "Breather · Break time") } && Set(rests.map(\.windowNumber)) == self.smokeRestWindowNumbers
            self.smokeLanguageChecks["\(prefix)RestMessageRawPreserved"] = self.model.settings.restMessage == rawMessage
            self.smokeLanguageChecks["\(prefix)RestMessageDisplayed"] = self.model.localizedRestMessage == language.restMessage(rawMessage)
            let defaultMessage = MonitorSettings().restMessage
            self.smokeLanguageChecks["\(prefix)DefaultRestMessageLocalized"] = language.restMessage(defaultMessage) == choose(defaultMessage, "Look into the distance and step away from the screen")
            do {
                self.smokeLanguageChecks["\(prefix)LanguageSaved"] = try self.model.persistedIsolatedLanguage() == language
                let restarted = self.model.reloadedIsolatedModel()
                self.smokeLanguageChecks["\(prefix)LanguageReloaded"] = restarted?.isolated == true && restarted?.language == language && restarted?.errorMessage == nil
                self.smokeLanguageChecks["\(prefix)RestMessageReloaded"] = restarted?.settings.restMessage == rawMessage
                let customMessage = "Custom rest message · 原样保留"
                self.model.settings.restMessage = customMessage
                self.model.saveSettings()
                let customReloaded = self.model.reloadedIsolatedModel()
                self.smokeLanguageChecks["\(prefix)CustomRestMessagePreserved"] = self.model.localizedRestMessage == customMessage && customReloaded?.settings.restMessage == customMessage && customReloaded?.localizedRestMessage == customMessage
                self.model.settings.restMessage = rawMessage
                self.model.saveSettings()
                try self.capture("language-\(prefix).png", directory: output)
                self.smokeLanguageSteps(languages, index: index + 1, output: output, completion: completion)
            } catch { self.smokeFailure(error) }
        }
    }
    private func smokeActions(output: URL) {
        model.settings.theme = .light; model.settings.restSeconds = 5; model.settings.reminderStyle = .mini
        model.settings.strictMode = false; model.settings.skipChallengeEnabled = false; model.saveSettings()
        let originalLanguage = model.language
        model.takeBreak()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                let rests = self.visibleRestWindows
                if let content = rests.first?.contentView { try self.capture("rest.png", directory: output, source: content) }
                let presented = !rests.isEmpty && self.model.engine.phase == .resting
                self.smokeRestWindowNumbers = Set(rests.map(\.windowNumber))
                self.smokeLanguageSteps([.chinese, .english, originalLanguage], output: output) {
                    self.smokeLanguageChecks["originalLanguageRestored"] = self.model.language == originalLanguage
                    self.finishSmokeActions(output: output, presented: presented)
                }
            } catch { self.smokeFailure(error) }
        }
    }
    private func finishSmokeActions(output: URL, presented: Bool) {
        model.skipBreak()
        let skipped = model.today.breaksSkipped > 0 && model.engine.phase == .snoozed
        model.pauseResume(); let paused = model.isPaused
        model.pauseResume(); let resumed = !model.isPaused
        let before = model.today.breaksCompleted
        model.settings.strictMode = true; model.settings.reminderStyle = .fullscreen; model.saveSettings(); model.takeBreak()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let content = self.visibleRestWindows.first?.contentView {
                do { try self.capture("rest-fullscreen.png", directory: output, source: content) }
                catch { self.smokeFailure(error) }
            }
        }
        model.skipBreak(); model.pauseResume()
        if let rest = visibleRestWindows.first {
            rest.makeKeyAndOrderFront(nil)
            smokeShortcutChecks["strictCloseKeyConsumed"] = performShortcut("w")
            smokeShortcutChecks["strictRestNotClosed"] = rest.isVisible && model.engine.phase == .resting
            rest.performMiniaturize(nil)
            smokeShortcutChecks["strictRestNotMinimized"] = !rest.isMiniaturized && rest.isVisible
        }
        let strict = model.engine.phase == .resting
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            let completed = self.model.today.breaksCompleted == before + 1
            let closed = self.visibleRestWindows.isEmpty
            let languageSwitchWorks = ["chinese", "english"].allSatisfy { prefix in
                ["MainMenu", "EditMenu", "StatusMenu", "MainWindow", "RestWindow"].allSatisfy {
                    self.smokeLanguageChecks["\(prefix)\($0)"] == true
                }
            }
            let languagePersists = ["chinese", "english"].allSatisfy { prefix in
                ["LanguageSaved", "LanguageReloaded", "RestMessageReloaded"].allSatisfy {
                    self.smokeLanguageChecks["\(prefix)\($0)"] == true
                }
            }
            let languagePassed = languageSwitchWorks && languagePersists && self.smokeLanguageChecks.values.allSatisfy { $0 }
            let dockPassed = self.smokeDockChecks.count == 10 && self.smokeDockChecks.values.allSatisfy { $0 }
            let activityPassed = self.smokeActivityChecks.count == 7 && self.smokeActivityChecks.values.allSatisfy { $0 }
            let shortcutsPassed = self.smokeShortcutChecks.count >= 7 && self.smokeShortcutChecks.values.allSatisfy { $0 }
            let dockRejectionPassed = self.dockRejectionChecks.count == 6 && self.dockRejectionChecks.values.allSatisfy { $0 }
            let csvHasHeader = CSVExporter.render(self.model.records).hasPrefix("date,active_seconds")
            let report: [String: Any] = [
                "windowVisible": self.window.isVisible,
                "restWindowPresented": presented,
                "skipRecorded": skipped,
                "pauseWorked": paused,
                "resumeWorked": resumed,
                "strictRefusal": strict,
                "restCompleted": completed,
                "restWindowClosed": closed,
                "isolatedStorage": self.model.isolated,
                "csvHasHeader": csvHasHeader,
                "language": self.model.language.rawValue,
                "languageChecks": self.smokeLanguageChecks,
                "languageSwitchWorks": languageSwitchWorks,
                "languagePersists": languagePersists,
                "languageChecksPassed": languagePassed,
                "dockVisibilityChecks": self.smokeDockChecks,
                "dockVisibilityPassed": dockPassed,
                "activityDetectionChecks": self.smokeActivityChecks,
                "activityDetectionPassed": activityPassed,
                "shortcutChecks": self.smokeShortcutChecks,
                "shortcutsPassed": shortcutsPassed,
                "dockRejectionChecks": self.dockRejectionChecks,
                "dockRejectionPassed": dockRejectionPassed,
                "errors": self.model.errorMessage ?? "",
                "passed": presented && skipped && paused && resumed && strict && completed && closed && self.model.isolated && csvHasHeader && languagePassed && dockPassed && activityPassed && shortcutsPassed && dockRejectionPassed && self.model.errorMessage == nil
            ]
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("smoke-report.json"))
                self.model.stop(); NSApp.terminate(nil)
            } catch { self.smokeFailure(error) }
        }
    }
    private func smokeFailure(_ error: Error) {
        fputs("EyeWatch smoke failed: \(error)\n", stderr)
        model.stop(); exit(1)
    }
}
