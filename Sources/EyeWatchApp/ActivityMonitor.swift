import AppKit
import ApplicationServices
import Combine
import CoreMedia
import CoreVideo
import EyeWatchCore
import ScreenCaptureKit

/// Optional evidence of computer activity, not a physical-presence detector.
/// AppModel remains responsible for independent sleep, lock, session and pause state.
@MainActor
final class ActivityMonitor: ObservableObject {
    @Published private(set) var accessibilityAuthorized = false
    @Published private(set) var screenRecordingAuthorized = false
    @Published private(set) var inputMonitoringRunning = false
    @Published private(set) var screenMonitoringRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var suspended = true

    private let isolated: Bool
    private var settings = MonitorSettings()
    private var configured = false
    private var lastPermissionPoll = -Double.infinity
    private let permissionPollInterval: Double = 5
    private let failureRetryInterval: Double = 10
    private var inputRetryAfter: Double = 0
    private var screenRetryAfter: Double = 0
    private var inputFailure: (String, String)?
    private var screenFailure: (String, String)?
    private var settingsFailure: (String, String)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var inputGeneration = 0
    private var screenGeneration = 0
    private var lastInputUptime: Double?
    private var screenActivityUptimes: [CGDirectDisplayID: Double] = [:]
    private var captureTask: Task<Void, Never>?
    private var displayObserver: NSObjectProtocol?
    private let frameQueue = DispatchQueue(label: "local.eyewatch.activity-grids", qos: .utility)

    private struct CaptureSession {
        let stream: SCStream
        let receiver: ActivityFrameReceiver
        var started = false
        var usable: Bool?
    }
    private var sessions: [CGDirectDisplayID: CaptureSession] = [:]
    // Retain only our own descriptor for this process lifetime. Closing the main window
    // must not prevent its exclusion when a later resume enumerates shareable content.
    private var ownApplicationDescriptor: SCRunningApplication?
    private var uptime: Double { ProcessInfo.processInfo.systemUptime }
    private var wantsInput: Bool {
        configured && !isolated && !suspended && settings.enhancedInputDetection && accessibilityAuthorized
    }
    private var wantsScreen: Bool {
        configured && !isolated && !suspended && settings.screenActivityDetection && screenRecordingAuthorized
    }

    init(isolated: Bool) { self.isolated = isolated }

    /// Idempotent on the one-second model tick. This method never asks for permission.
    func configure(settings: MonitorSettings, screenAvailable: Bool) {
        self.settings = settings
        configured = true
        if suspended != !screenAvailable { suspended = !screenAvailable }
        if isolated {
            // Do not even query the owner's permission state in isolated previews or smoke runs.
            clearIsolatedState()
            return
        }
        pollPermissions(force: false)
        reconcile()
    }

    func signals(systemIdleSeconds: Double) -> ActivitySignals {
        guard !isolated else { return ActivitySignals(systemIdleSeconds: systemIdleSeconds) }
        let now = uptime
        let inputIdle = inputMonitoringRunning && wantsInput ? age(lastInputUptime, now: now) : nil
        let latestScreen = sessions.compactMap { id, session -> Double? in
            guard session.started, session.usable != false else { return nil }
            return screenActivityUptimes[id]
        }.max()
        let screenIdle = screenMonitoringRunning && wantsScreen ? age(latestScreen, now: now) : nil
        return ActivitySignals(
            systemIdleSeconds: systemIdleSeconds,
            inputIdleSeconds: inputIdle,
            screenChangeIdleSeconds: screenIdle,
            accessibilityGranted: accessibilityAuthorized,
            inputMonitorRunning: inputMonitoringRunning,
            screenRecordingGranted: screenRecordingAuthorized,
            screenMonitorRunning: screenMonitoringRunning
        )
    }

    /// Explicit refresh is read-only; returning from System Settings does not trigger a prompt.
    func refreshPermissions() {
        guard !isolated else { clearIsolatedState(); return }
        pollPermissions(force: true)
        inputRetryAfter = 0; screenRetryAfter = 0
        reconcile()
    }

    /// Only an explicit user action may call this prompt-capable API.
    func requestAccessibilityPermission() {
        guard !isolated else { clearIsolatedState(); return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
    }

    /// Only an explicit user action may call this prompt-capable API.
    func requestScreenRecordingPermission() {
        guard !isolated else { clearIsolatedState(); return }
        _ = CGRequestScreenCaptureAccess()
        refreshPermissions()
    }

    func openAccessibilitySettings() { openSettings("Privacy_Accessibility") }
    func openScreenRecordingSettings() { openSettings("Privacy_ScreenCapture") }

    func stop() {
        configured = false
        if !suspended { suspended = true }
        stopInput()
        stopCapture()
        removeDisplayObserver()
        inputRetryAfter = 0; screenRetryAfter = 0
        lastPermissionPoll = -Double.infinity
        inputFailure = nil; screenFailure = nil; settingsFailure = nil
        publishError()
    }

    private func age(_ timestamp: Double?, now: Double) -> Double? {
        guard let timestamp, timestamp.isFinite, timestamp >= 0, timestamp <= now else { return nil }
        return now - timestamp
    }
    private func pollPermissions(force: Bool) {
        guard !isolated else { return }
        let now = uptime
        guard force || now - lastPermissionPoll >= permissionPollInterval else { return }
        lastPermissionPoll = now
        let inputGranted = AXIsProcessTrusted()
        let screenGranted = CGPreflightScreenCaptureAccess()
        if accessibilityAuthorized != inputGranted { accessibilityAuthorized = inputGranted }
        if screenRecordingAuthorized != screenGranted { screenRecordingAuthorized = screenGranted }
    }
    private func reconcile() {
        if wantsInput {
            if !inputMonitoringRunning && uptime >= inputRetryAfter { startInput() }
        } else {
            if globalMonitor != nil || localMonitor != nil || lastInputUptime != nil { stopInput() }
            inputRetryAfter = 0; inputFailure = nil
        }
        if wantsScreen {
            installDisplayObserver()
            if sessions.isEmpty && captureTask == nil && uptime >= screenRetryAfter { startCapture() }
        } else {
            if captureTask != nil || !sessions.isEmpty || !screenActivityUptimes.isEmpty { stopCapture() }
            removeDisplayObserver()
            screenRetryAfter = 0; screenFailure = nil
        }
        publishError()
    }
    private func startInput() {
        guard wantsInput, globalMonitor == nil, localMonitor == nil else { return }
        inputGeneration += 1
        let generation = inputGeneration
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp, .flagsChanged, .mouseMoved, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            // Never retain the event or inspect keys, text, pointer position or target application.
            let timestamp = event.timestamp
            Task { @MainActor [weak self] in self?.recordInput(timestamp, generation: generation) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let timestamp = event.timestamp
            Task { @MainActor [weak self] in self?.recordInput(timestamp, generation: generation) }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else {
            stopInput()
            inputFailure = ("增强键鼠监听未能启动，仍使用系统空闲时间。", "Enhanced input monitoring could not start. System idle detection is still available.")
            inputRetryAfter = uptime + failureRetryInterval
            publishError()
            return
        }
        lastInputUptime = nil // Enabling a monitor is not an input event.
        inputMonitoringRunning = true
        inputFailure = nil
    }
    private func recordInput(_ timestamp: Double, generation: Int) {
        guard generation == inputGeneration, wantsInput, inputMonitoringRunning,
              timestamp.isFinite, timestamp >= 0, timestamp <= uptime else { return }
        lastInputUptime = max(lastInputUptime ?? timestamp, timestamp)
    }
    private func stopInput() {
        inputGeneration += 1
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; lastInputUptime = nil
        if inputMonitoringRunning { inputMonitoringRunning = false }
    }

    private func startCapture() {
        guard wantsScreen, captureTask == nil, sessions.isEmpty else { return }
        // Enumeration may itself be permission-sensitive. Do not call it on an ungranted path.
        guard CGPreflightScreenCaptureAccess() else { screenAccessLost(); return }
        screenGeneration += 1
        let generation = screenGeneration
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.screenGeneration == generation { self.captureTask = nil } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard self.currentCapture(generation), !Task.isCancelled else { return }
                let ownPID = ProcessInfo.processInfo.processIdentifier
                // Inspect only PID ownership, never window titles or other applications' metadata.
                // Offscreen windows may still supply our descriptor after the main window closes.
                if let ownApplication = content.applications.first(where: { $0.processID == ownPID })
                    ?? content.windows.lazy.compactMap({ $0.owningApplication }).first(where: { $0.processID == ownPID }) {
                    self.ownApplicationDescriptor = ownApplication
                }
                guard let ownApplication = self.ownApplicationDescriptor, ownApplication.processID == ownPID else {
                    self.captureFailed(generation, message: nil, ownApplicationMissing: true)
                    return
                }
                let ownApplications = [ownApplication]
                guard !content.displays.isEmpty else {
                    self.captureFailed(generation, message: nil)
                    return
                }
                for display in content.displays {
                    guard self.currentCapture(generation), !Task.isCancelled else { return }
                    guard CGPreflightScreenCaptureAccess() else { self.screenAccessLost(); return }
                    let id = display.displayID
                    let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
                    if #available(macOS 14.2, *) { filter.includeMenuBar = false }
                    let configuration = SCStreamConfiguration()
                    // Preserve each display's aspect ratio while limiting the longer edge to 160px.
                    let displayWidth = max(1, display.width), displayHeight = max(1, display.height)
                    let scale = 160.0 / Double(max(displayWidth, displayHeight))
                    configuration.width = max(32, Int((Double(displayWidth) * scale).rounded()))
                    configuration.height = max(18, Int((Double(displayHeight) * scale).rounded()))
                    configuration.minimumFrameInterval = CMTime(seconds: 2, preferredTimescale: 600)
                    configuration.pixelFormat = kCVPixelFormatType_32BGRA
                    configuration.colorSpaceName = CGColorSpace.sRGB
                    configuration.queueDepth = 3
                    configuration.showsCursor = false
                    configuration.capturesAudio = false
                    configuration.excludesCurrentProcessAudio = true
                    if #available(macOS 15.0, *) {
                        configuration.captureMicrophone = false
                        configuration.showMouseClicks = false
                    }
                    let receiver = ActivityFrameReceiver(queue: self.frameQueue, onState: { [weak self] usable, activity in
                        Task { @MainActor [weak self] in
                            self?.receiveFrameState(usable, activity: activity, display: id, generation: generation)
                        }
                    }, onError: { [weak self] message in
                        Task { @MainActor [weak self] in self?.captureFailed(generation, message: message) }
                    })
                    let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
                    try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: self.frameQueue)
                    // Keep pending streams so stop/suspend can invalidate them before startCapture returns.
                    self.sessions[id] = CaptureSession(stream: stream, receiver: receiver)
                    do {
                        try await stream.startCapture()
                    } catch {
                        // A stop request can race the OS start completion. Stop again after that
                        // completion, even if this task or generation was invalidated meanwhile.
                        receiver.invalidate()
                        try? stream.removeStreamOutput(receiver, type: .screen)
                        try? await stream.stopCapture()
                        throw error
                    }
                    guard self.currentCapture(generation), !Task.isCancelled else {
                        receiver.invalidate()
                        try? stream.removeStreamOutput(receiver, type: .screen)
                        try? await stream.stopCapture()
                        return
                    }
                    self.sessions[id]?.started = true
                    self.updateCaptureRunning()
                }
                self.screenFailure = nil
                self.publishError()
            } catch {
                if self.currentCapture(generation), !Task.isCancelled {
                    self.captureFailed(generation, message: error.localizedDescription)
                }
            }
        }
    }
    private func screenAccessLost() {
        if screenRecordingAuthorized { screenRecordingAuthorized = false }
        stopCapture()
        screenRetryAfter = uptime + failureRetryInterval
        screenFailure = nil
        publishError()
    }
    private func currentCapture(_ generation: Int) -> Bool { generation == screenGeneration && wantsScreen }
    private func receiveFrameState(_ usable: Bool, activity: Double?, display: CGDirectDisplayID, generation: Int) {
        guard currentCapture(generation), var session = sessions[display] else { return }
        session.usable = usable
        sessions[display] = session
        if usable, let activity, activity.isFinite, activity >= 0, activity <= uptime {
            screenActivityUptimes[display] = max(screenActivityUptimes[display] ?? activity, activity)
        } else if !usable {
            screenActivityUptimes.removeValue(forKey: display)
        }
        updateCaptureRunning()
    }
    private func updateCaptureRunning() {
        let running = wantsScreen && sessions.values.contains { $0.started && $0.usable != false }
        if screenMonitoringRunning != running { screenMonitoringRunning = running }
    }
    private func captureFailed(_ generation: Int, message: String?, ownApplicationMissing: Bool = false) {
        guard currentCapture(generation) else { return }
        stopCapture()
        pollPermissions(force: true)
        screenRetryAfter = uptime + failureRetryInterval
        if ownApplicationMissing {
            screenFailure = ("无法确认排除歇会儿自身窗口，屏幕采样未启动。请打开歇会儿主窗口后，点击刷新权限重试。", "Screen sampling did not start because Breather's own windows could not be safely excluded. Open Breather's main window, then refresh permissions to try again.")
        } else if let message {
            screenFailure = ("屏幕采样已停止，仍使用系统空闲时间：\(message)", "Screen sampling stopped. System idle detection is still available: \(message)")
        } else {
            screenFailure = ("屏幕采样不可用或已停止，仍使用系统空闲时间。", "Screen sampling is unavailable or has stopped. System idle detection is still available.")
        }
        publishError()
    }
    private func stopCapture() {
        screenGeneration += 1
        captureTask?.cancel(); captureTask = nil
        let oldSessions = Array(sessions.values)
        sessions.removeAll(); screenActivityUptimes.removeAll()
        if screenMonitoringRunning { screenMonitoringRunning = false }
        for session in oldSessions {
            // Synchronously erase the detector and disable queued callbacks before stopping the stream.
            session.receiver.invalidate()
            try? session.stream.removeStreamOutput(session.receiver, type: .screen)
            session.stream.stopCapture { _ in }
        }
    }
    private func installDisplayObserver() {
        guard displayObserver == nil else { return }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsScreen else { return }
                self.stopCapture()
                self.screenRetryAfter = 0
                self.reconcile() // Fresh per-display baselines; topology changes do not count as activity.
            }
        }
    }
    private func removeDisplayObserver() {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
    }
    private func openSettings(_ pane: String) {
        guard !isolated else { clearIsolatedState(); return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"), NSWorkspace.shared.open(url) else {
            settingsFailure = ("无法打开系统隐私设置，请手动打开系统设置 → 隐私与安全性。", "Could not open privacy settings. Open System Settings → Privacy & Security manually.")
            publishError()
            return
        }
        settingsFailure = nil; publishError()
    }
    private func clearIsolatedState() {
        if accessibilityAuthorized { accessibilityAuthorized = false }
        if screenRecordingAuthorized { screenRecordingAuthorized = false }
        if inputMonitoringRunning { inputMonitoringRunning = false }
        if screenMonitoringRunning { screenMonitoringRunning = false }
        lastInputUptime = nil; screenActivityUptimes.removeAll()
        inputFailure = nil; screenFailure = nil; settingsFailure = nil
        publishError()
    }
    private func publishError() {
        let errors = [inputFailure, screenFailure, settingsFailure].compactMap { $0 }.map { settings.language.choose($0.0, $0.1) }
        let message = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if lastError != message { lastError = message }
    }
    deinit {
        captureTask?.cancel()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        let global = globalMonitor, local = localMonitor
        DispatchQueue.main.async {
            if let global { NSEvent.removeMonitor(global) }
            if let local { NSEvent.removeMonitor(local) }
        }
        for session in sessions.values {
            session.receiver.invalidate()
            try? session.stream.removeStreamOutput(session.receiver, type: .screen)
            session.stream.stopCapture { _ in }
        }
    }
}

/// All mutable frame state belongs to the supplied serial queue. No pixel buffer, image,
/// grid, window metadata or application metadata is ever forwarded to the main actor.
private final class ActivityFrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue: DispatchQueue
    private let onState: @Sendable (Bool, Double?) -> Void
    private let onError: @Sendable (String?) -> Void
    private var enabled = true
    private var detector = ScreenChangeDetector()
    private var pixelSize: (Int, Int)?
    private var lastUsable: Bool?

    init(queue: DispatchQueue, onState: @escaping @Sendable (Bool, Double?) -> Void, onError: @escaping @Sendable (String?) -> Void) {
        self.queue = queue; self.onState = onState; self.onError = onError
        super.init()
    }
    func invalidate() {
        queue.sync {
            enabled = false; detector.reset(); pixelSize = nil; lastUsable = nil
        }
    }
    private func emit(usable: Bool, activity: Double? = nil) {
        if lastUsable != usable || activity != nil { onState(usable, activity) }
        lastUsable = usable
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard enabled, type == .screen, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: rawStatus) else { return }
        switch status {
        case .idle:
            emit(usable: true) // A live, unchanged stream is not activity.
        case .blank, .suspended:
            detector.reset(); pixelSize = nil
            emit(usable: false)
        case .stopped:
            enabled = false; detector.reset(); pixelSize = nil
            emit(usable: false); onError(nil)
        case .complete, .started:
            guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer), let grid = grayscaleGrid(pixels) else {
                detector.reset(); pixelSize = nil; emit(usable: false)
                return
            }
            let size = (CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels))
            if pixelSize?.0 != size.0 || pixelSize?.1 != size.1 { detector.reset(); pixelSize = size }
            let changed = detector.observe(grid) // A first/reconfigured frame only establishes a baseline.
            emit(usable: true, activity: changed ? ProcessInfo.processInfo.systemUptime : nil)
        @unknown default:
            detector.reset(); pixelSize = nil; emit(usable: false)
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            self.enabled = false; self.detector.reset(); self.pixelSize = nil
            self.emit(usable: false); self.onError(message)
        }
    }
    private func grayscaleGrid(_ pixels: CVPixelBuffer) -> [UInt8]? {
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        guard width >= 32, height >= 18, stride >= width * 4, let base = CVPixelBufferGetBaseAddress(pixels) else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var grid = [UInt8](repeating: 0, count: 32 * 18)
        for row in 0..<18 {
            let y0 = row * height / 18, y1 = (row + 1) * height / 18
            for column in 0..<32 {
                let x0 = column * width / 32, x1 = (column + 1) * width / 32
                var total = 0, count = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let offset = y * stride + x * 4
                        total += (77 * Int(bytes[offset + 2]) + 150 * Int(bytes[offset + 1]) + 29 * Int(bytes[offset])) >> 8
                        count += 1
                    }
                }
                grid[row * 32 + column] = UInt8(total / max(1, count))
            }
        }
        return grid
    }
}
