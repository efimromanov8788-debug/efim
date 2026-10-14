// Рисует иконку программы тем же кодом, что и котов. Вызывается при сборке:
// Murka --render-icon <папка.iconset>, потом iconutil собирает из PNG файл .icns.

import AppKit

@MainActor
enum IconRenderer {
    static let sizes: [(String, Int)] = [
        ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
        ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
        ("512x512", 512), ("512x512@2x", 1024),
    ]

    static func render(to folder: String) {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, px) in sizes {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            rep.size = NSSize(width: px, height: px)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            drawIcon(size: CGFloat(px))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("icon_\(name).png"))
            }
        }
    }

    static func drawIcon(size: CGFloat) {
        let inset = size * 0.09
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
        let top = NSColor(srgbRed: 1.0, green: 0.86, blue: 0.62, alpha: 1)
        let bottom = NSColor(srgbRed: 0.98, green: 0.6, blue: 0.45, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: tile, angle: 90)

        let pose = CatPose(state: .idle, time: 0.4, facingRight: true, surface: .floor, onGround: true,
                           lookX: 0.6, lookY: 0.4, blinking: false)
        CatRenderer.draw(look: Presets.murka.look, pose: pose, in: rect,
                         baseY: rect.minY + rect.height * 0.2, zoom: rect.width / 118)
    }
}
