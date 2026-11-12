import AppKit

// Mujian uses the same 1024-unit, top-left coordinate system as Mujian.svg.
// Render directly into an explicit bitmap so points never become Retina pixels.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
if !(2...3).contains(arguments.count) {
    fail("Usage: swift scripts/make-icon.swift <output.png> [pixel-size]")
}
let pixelSize: Int
if arguments.count == 3 {
    guard let requestedSize = Int(arguments[2]), (16...4096).contains(requestedSize) else {
        fail("Pixel size must be an integer between 16 and 4096")
    }
    pixelSize = requestedSize
} else {
    pixelSize = 1024
}

guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("Could not create the sRGB color space")
}
guard let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: pixelSize * 4,
    space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("Could not create the icon bitmap")
}

context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
context.translateBy(x: 0, y: CGFloat(pixelSize))
let scale = CGFloat(pixelSize) / 1024
context.scaleBy(x: scale, y: -scale)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(colorSpace: sRGB, components: [red / 255, green / 255, blue / 255, 1])!
}

context.setFillColor(color(248, 247, 244)) // Paper #F8F7F4
context.addPath(CGPath(
    roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
    cornerWidth: 192,
    cornerHeight: 192,
    transform: nil
))
context.fillPath()

// One compound path avoids antialiased seams where the window bars meet.
let window = CGMutablePath()
window.move(to: CGPoint(x: 256, y: 256))
window.addLine(to: CGPoint(x: 768, y: 256))
window.addLine(to: CGPoint(x: 768, y: 544))
window.addLine(to: CGPoint(x: 704, y: 544))
window.addLine(to: CGPoint(x: 704, y: 320))
window.addLine(to: CGPoint(x: 544, y: 320))
window.addLine(to: CGPoint(x: 544, y: 704))
window.addLine(to: CGPoint(x: 576, y: 704))
window.addLine(to: CGPoint(x: 576, y: 768))
window.addLine(to: CGPoint(x: 256, y: 768))
window.closeSubpath()
window.addRect(CGRect(x: 320, y: 320, width: 160, height: 80))
window.addRect(CGRect(x: 320, y: 448, width: 160, height: 128))
window.addRect(CGRect(x: 320, y: 624, width: 160, height: 80))
context.setFillColor(color(36, 37, 35)) // Ink #242523
context.addPath(window)
context.drawPath(using: .eoFill)

context.setFillColor(color(163, 79, 55)) // Interval #A34F37
context.fill(CGRect(x: 640, y: 704, width: 128, height: 64))

guard let cgImage = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
    fail("Could not encode the icon PNG")
}
do {
    try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
    print("Rendered Mujian icon: \(pixelSize) × \(pixelSize) px → \(arguments[1])")
} catch {
    fail("Could not write the icon: \(error.localizedDescription)")
}
