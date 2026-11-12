import SwiftUI
import AppKit

// Product-specific visual system. No business state or persistence lives here.
enum MujianStyle {
    static let paper = adaptive(0xF8F8F6, 0x171816)
    static let sidebar = adaptive(0xEFEFEB, 0x111210)
    static let surface = adaptive(0xFFFFFF, 0x1E1F1C)
    static let raised = adaptive(0xE9EAE5, 0x2B2D27)
    static let ink = adaptive(0x252621, 0xE9E9E3)
    static let secondary = adaptive(0x62645D, 0xABADA4)
    static let muted = adaptive(0x6B6D65, 0x93968C)
    static let accent = adaptive(0xA34F37, 0xD79275)
    static let rule = ink.opacity(0.11)
    static let chart = adaptive(0xA5A89F, 0x74796D)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let feedback = Animation.easeOut(duration: 0.16)
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct MujianMark: View {
    var size: CGFloat = 28
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 576
            let point: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: (x - 224) * s, y: (y - 224) * s) }
            ZStack {
                Path { p in
                    p.move(to: point(256,256)); p.addLine(to: point(768,256)); p.addLine(to: point(768,544))
                    p.addLine(to: point(704,544)); p.addLine(to: point(704,320)); p.addLine(to: point(544,320))
                    p.addLine(to: point(544,704)); p.addLine(to: point(576,704)); p.addLine(to: point(576,768))
                    p.addLine(to: point(256,768)); p.closeSubpath()
                    for (y, height) in [(320.0,80.0), (448.0,128.0), (624.0,80.0)] {
                        p.addRect(CGRect(x: (320-224)*s, y: (y-224)*s, width: 160*s, height: height*s))
                    }
                }.fill(MujianStyle.ink, style: FillStyle(eoFill: true))
                Rectangle().fill(MujianStyle.accent).frame(width: 128*s, height: 64*s)
                    .position(x: (704-224)*s, y: (736-224)*s)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16).frame(minHeight: 36)
            .foregroundStyle(primary ? MujianStyle.paper : MujianStyle.ink)
            .background(primary ? MujianStyle.ink.opacity(configuration.isPressed ? 0.80 : 1) : (hovered || configuration.isPressed ? MujianStyle.raised : Color.clear), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? MujianStyle.accent : (primary ? .clear : MujianStyle.rule), lineWidth: focused ? 2 : 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : MujianStyle.feedback, value: hovered)
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(MujianStyle.ink)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Spacer(minLength: 8)
            if !detail.isEmpty {
                Text(detail).font(MujianStyle.caption).foregroundStyle(MujianStyle.muted)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(MujianStyle.rule).frame(height: 1).accessibilityHidden(true) }
}
