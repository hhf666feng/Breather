import AppKit
import Combine
import SwiftUI
import EyeWatchCore
import UserNotifications

@MainActor
final class BreakPresenter {
    private weak var model: AppModel?
    private var panels: [NSPanel] = []
    private var languageSubscription: AnyCancellable?
    init(model: AppModel) {
        self.model = model
        languageSubscription = model.$settings.map { $0.language }.removeDuplicates().sink { [weak self] _ in
            // @Published emits before the stored settings change.
            DispatchQueue.main.async { self?.updateLanguage() }
        }
    }
    private func updateLanguage() {
        guard let model else { return }
        for panel in panels { panel.title = model.text("歇会儿 · 休息时间", "Breather · Break time") }
    }
    func show() {
        guard let model else { return }
        dismiss()
        if model.settings.soundEnabled && !model.isolated { NSSound(named: "Glass")?.play() }
        // An explicit rest always presents a countdown, including when automatic reminders use notifications.
        showPanels(fullscreen: model.settings.reminderStyle == .fullscreen)
    }
    func notifyRest() {
        guard let model else { return }
        notify(title: model.text("该让眼睛休息一下了", "Time to rest your eyes"), body: model.localizedRestMessage, fallbackToRest: true)
    }
    func notify(title: String, body: String, fallbackToRest: Bool = false) {
        guard let model, !model.isolated else { return }
        let generation = model.reminderGeneration
        Task { @MainActor [weak self] in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if fallbackToRest && !model.isReminderCurrent(generation) { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                if fallbackToRest {
                    model.errorMessage = model.text("通知权限未开启，已改用迷你休息窗口。请在系统设置 → 通知中允许歇会儿。", "Notifications are disabled, so a mini break window is shown instead. Allow Breather in System Settings → Notifications.")
                    model.takeBreak()
                }
                return
            }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body
            if model.settings.soundEnabled { content.sound = .default }
            do { try await center.add(UNNotificationRequest(identifier: "eyewatch-rest", content: content, trigger: nil)) }
            catch {
                model.errorMessage = model.text("通知发送失败：\(error.localizedDescription)", "Could not send the notification: \(error.localizedDescription)")
                if fallbackToRest && model.isReminderCurrent(generation) { self?.model?.takeBreak() }
            }
        }
    }
    private func showPanels(fullscreen: Bool) {
        guard let model, model.engine.phase == .resting else { return }
        let screens = fullscreen ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        for screen in screens {
            let frame: NSRect
            if fullscreen { frame = screen.frame }
            else { frame = NSRect(x: screen.visibleFrame.midX - 270, y: screen.visibleFrame.midY - 260, width: 540, height: 520) }
            let panel = RestPanel(contentRect: frame, styleMask: fullscreen ? [.borderless] : [.titled], backing: .buffered, defer: false)
            panel.closeRequested = { [weak model] in model?.skipBreak() }
            panel.identifier = NSUserInterfaceItemIdentifier("mujian.rest")
            panel.title = model.text("歇会儿 · 休息时间", "Breather · Break time")
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: LanguageRoot(model: model) {
                RestContent(model: model, fullscreen: fullscreen)
            })
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func dismiss() {
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        if model?.isolated == false { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["eyewatch-rest"]) }
    }
}
private final class RestPanel: NSPanel {
    var closeRequested: (() -> Void)?
    override var canBecomeKey: Bool { true }
    // Window commands must follow the same skip/challenge/strict policy as the buttons.
    override func performClose(_ sender: Any?) { closeRequested?() }
    override func performMiniaturize(_ sender: Any?) { /* Break windows stay visible until completed or skipped. */ }
    override func miniaturize(_ sender: Any?) { /* Do not hide an active break. */ }
    override func cancelOperation(_ sender: Any?) { closeRequested?() }
}

private struct RestContent: View {
    @ObservedObject var model: AppModel
    let fullscreen: Bool
    var body: some View {
        ZStack {
            Color(red: 0.085, green: 0.09, blue: 0.078)
            if let path = model.settings.wallpaperPath, let image = NSImage(contentsOfFile: path) {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    Color.black.opacity(0.65)
                }
            }
            VStack(spacing: fullscreen ? 32 : 20) {
                HStack(spacing: 12) {
                    MujianMark(size: 24)
                    Text(model.text("歇会儿", "Breather")).font(.custom("Songti SC", size: 22))
                }.foregroundStyle(MujianStyle.secondary)
                VStack(spacing: 12) {
                    Text(model.text("休息片刻", "Rest for a moment")).font(.system(size: fullscreen ? 44 : 28, weight: .regular))
                    Text(model.localizedRestMessage).font(.system(size: fullscreen ? 16 : 13))
                        .foregroundStyle(MujianStyle.secondary).multilineTextAlignment(.center).lineLimit(fullscreen ? 4 : 3)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560)
                }
                VStack(spacing: 16) {
                    Text(AppModel.clock(model.engine.breakRemaining)).font(.system(size: fullscreen ? 104 : 64, weight: .regular)).monospacedDigit()
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.14))
                            Rectangle().fill(MujianStyle.accent).frame(width: proxy.size.width * min(1, max(0, 1 - model.engine.breakRemaining / model.settings.restSeconds)))
                        }
                    }.frame(width: fullscreen ? 280 : 200, height: 2)
                }
                Text(model.text("望向 6 米外 · 放松肩颈 · 慢慢眨眼", "Look 6 metres away · Relax your shoulders · Blink slowly"))
                    .font(.system(size: 12)).foregroundStyle(MujianStyle.secondary).multilineTextAlignment(.center)
                if model.engine.breakIsStrict {
                    Text(model.text("本次休息不可跳过，结束后自动返回", "This break cannot be skipped. It will close when the timer ends."))
                        .font(.system(size: 12)).foregroundStyle(MujianStyle.muted).multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 12) {
                        Button(model.text("延后 5 分钟", "Snooze for 5 minutes"), action: model.snooze)
                        Button(model.text("跳过本次", "Skip this break"), action: model.skipBreak)
                    }.buttonStyle(QuietButtonStyle())
                }
                Button(model.text("退出歇会儿", "Quit Breather")) { model.stop(); NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(MujianStyle.muted)
            }.padding(32)
        }
        .foregroundStyle(MujianStyle.ink).preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
