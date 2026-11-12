import Foundation

public enum ActivitySource: String, Codable, CaseIterable {
    case systemInput, enhancedInput, screenChanges, idle, unavailable, continuous
}

public struct ActivitySignals {
    public var systemIdleSeconds: Double
    public var inputIdleSeconds: Double?
    public var screenChangeIdleSeconds: Double?
    public var accessibilityGranted: Bool
    public var inputMonitorRunning: Bool
    public var screenRecordingGranted: Bool
    public var screenMonitorRunning: Bool
    public init(systemIdleSeconds: Double, inputIdleSeconds: Double? = nil, screenChangeIdleSeconds: Double? = nil, accessibilityGranted: Bool = false, inputMonitorRunning: Bool = false, screenRecordingGranted: Bool = false, screenMonitorRunning: Bool = false) {
        self.systemIdleSeconds = systemIdleSeconds; self.inputIdleSeconds = inputIdleSeconds; self.screenChangeIdleSeconds = screenChangeIdleSeconds
        self.accessibilityGranted = accessibilityGranted; self.inputMonitorRunning = inputMonitorRunning
        self.screenRecordingGranted = screenRecordingGranted; self.screenMonitorRunning = screenMonitorRunning
    }
}
public struct ActivityDecision: Equatable {
    public var idleSeconds: Double
    public var source: ActivitySource
    public var screenAvailable: Bool
    public init(idleSeconds: Double, source: ActivitySource, screenAvailable: Bool) { self.idleSeconds = idleSeconds; self.source = source; self.screenAvailable = screenAvailable }
}
public enum ActivityClassifier {
    public static func evaluate(_ signals: ActivitySignals, settings: MonitorSettings, screenAvailable: Bool) -> ActivityDecision {
        let threshold = settings.validated().idleSeconds
        var idle = validIdle(signals.systemIdleSeconds) ?? threshold
        guard screenAvailable else {
            return ActivityDecision(idleSeconds: max(idle, threshold), source: .unavailable, screenAvailable: false)
        }
        if settings.monitoringMode == .continuous {
            return ActivityDecision(idleSeconds: 0, source: .continuous, screenAvailable: true)
        }
        var source: ActivitySource = .systemInput
        if settings.enhancedInputDetection && signals.accessibilityGranted && signals.inputMonitorRunning,
           let input = signals.inputIdleSeconds.flatMap(validIdle), input < idle {
            idle = input; source = .enhancedInput
        }
        if settings.screenActivityDetection && signals.screenRecordingGranted && signals.screenMonitorRunning,
           let screen = signals.screenChangeIdleSeconds.flatMap(validIdle), screen < idle {
            idle = screen; source = .screenChanges
        }
        return ActivityDecision(idleSeconds: idle, source: idle >= threshold ? .idle : source, screenAvailable: true)
    }
    private static func validIdle(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }
}

/// Compares only caller-supplied, downsampled grayscale values; contains no capture or storage APIs.
public struct ScreenChangeDetector {
    private var previous: [UInt8]?
    public init() {}
    public mutating func observe(_ samples: [UInt8]) -> Bool {
        defer { previous = samples.isEmpty ? nil : samples }
        guard !samples.isEmpty, let previous, previous.count == samples.count else { return false }
        var changed = 0
        var totalDifference = 0
        for index in samples.indices {
            let difference = abs(Int(samples[index]) - Int(previous[index]))
            totalDifference += difference
            if difference >= 12 { changed += 1 }
        }
        return Double(changed) / Double(samples.count) >= 0.06 && Double(totalDifference) / Double(samples.count) >= 4
    }
    public mutating func reset() { previous = nil }
}
