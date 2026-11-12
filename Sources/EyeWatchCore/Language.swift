import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"
    public var id: String { rawValue }
    public var displayName: String { self == .chinese ? "简体中文" : "English" }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppLanguage(rawValue: raw) ?? .chinese
    }
    public func choose(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }
    public var locale: Locale { Locale(identifier: choose("zh_Hans_CN", "en_US")) }
    public func duration(_ seconds: Double) -> String {
        let rawMinutes = seconds / 60
        let minutes = rawMinutes.isFinite && rawMinutes >= 0 && rawMinutes < Double(Int.max) ? Int(rawMinutes) : 0
        if minutes < 60 { return choose("\(minutes) 分钟", "\(minutes) min") }
        let remainder = String(format: "%02d", minutes % 60)
        return choose("\(minutes / 60)时 \(remainder)分", "\(minutes / 60)h \(remainder)m")
    }
    public func restMessage(_ original: String) -> String {
        guard original == MonitorSettings().restMessage else { return original }
        return choose(original, "Look into the distance and step away from the screen")
    }
}
