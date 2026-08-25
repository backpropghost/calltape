// Generates CallTape's app icon as a .iconset folder.
// Usage: appicongen <output.iconset dir>
// Draws a rounded-square gradient with a white tape-reel glyph on top.

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    let side = CGFloat(pixels)

    // Rounded-square plate with a little padding, macOS-style.
    let pad = side * 0.085
    let rect = CGRect(x: pad, y: pad, width: side - 2 * pad, height: side - 2 * pad)
    let radius = rect.width * 0.2237
    let plate = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let colors = [
        CGColor(red: 0.35, green: 0.30, blue: 0.95, alpha: 1),
        CGColor(red: 0.55, green: 0.25, blue: 0.95, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    }
    ctx.restoreGState()

    // White tape-reel glyph, centered.
    if let symbol = NSImage(systemSymbolName: "recordingtape", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .regular)
            .applying(.init(paletteColors: [.white]))
        if let glyph = symbol.withSymbolConfiguration(config) {
            let size = glyph.size
            let origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
            glyph.draw(in: CGRect(origin: origin, size: size))
        }
    }

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])
}

// (filename, pixel size) pairs iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, pixels) in variants {
    guard let data = render(pixels) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("Wrote \(variants.count) icons to \(outDir)")
