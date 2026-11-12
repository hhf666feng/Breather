import CoreGraphics

/// The documented kCGAnyInputEventType selector includes keyboard, mouse and tablet input.
public enum SystemInputIdle {
    public static var eventType: CGEventType { CGEventType(rawValue: UInt32.max)! }
    public static func read() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
    }
}
