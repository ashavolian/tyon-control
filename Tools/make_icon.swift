// Renders the app icon (a mouse silhouette on a dark rounded square) at every size
// macOS wants and packs them into Resources/AppIcon.icns via iconutil.
import AppKit

func render(_ px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let inset = s * 0.08
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1),
               ending: NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: bg, angle: -90)

    // mouse body
    let bw = s * 0.42, bh = s * 0.62
    let bx = (s - bw) / 2, by = (s - bh) / 2 - s * 0.02
    let body = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh), xRadius: bw / 2, yRadius: bw / 2)
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    body.fill()

    // button split
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setStroke()
    let split = NSBezierPath()
    split.lineWidth = max(1, s * 0.022)
    split.move(to: NSPoint(x: s / 2, y: by + bh * 0.58))
    split.line(to: NSPoint(x: s / 2, y: by + bh))
    split.stroke()
    let bar = NSBezierPath()
    bar.lineWidth = max(1, s * 0.022)
    bar.move(to: NSPoint(x: bx, y: by + bh * 0.58))
    bar.line(to: NSPoint(x: bx + bw, y: by + bh * 0.58))
    bar.stroke()

    // glowing wheel
    let ww = s * 0.07, wh = s * 0.15
    let wheel = NSBezierPath(roundedRect: NSRect(x: s / 2 - ww / 2, y: by + bh * 0.66, width: ww, height: wh), xRadius: ww / 2, yRadius: ww / 2)
    NSColor(calibratedRed: 0.02, green: 0.56, blue: 1.0, alpha: 1).setFill()
    wheel.fill()
    img.unlockFocus()
    return img
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = render(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try! task.run(); task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "icon written" : "iconutil failed")
