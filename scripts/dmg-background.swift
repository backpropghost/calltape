// Draws the CallTape DMG install-window background.
// Usage: swift dmg-background.swift <scale> <output.png>
import AppKit

let scale = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 1) : 1
let out   = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "bg.png"

let W = 660, H = 400
let pw = W * scale, ph = H * scale
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

// Soft vertical gradient, light and clean.
let top = CGColor(red: 0.985, green: 0.986, blue: 0.992, alpha: 1)
let bot = CGColor(red: 0.940, green: 0.942, blue: 0.957, alpha: 1)
let grad = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: 0), options: [])

// Arrow between the two icon slots (icons sit at y = 195 from the top).
let ay = CGFloat(H - 195)
let arrow = CGColor(red: 0.62, green: 0.62, blue: 0.66, alpha: 1)
ctx.setStrokeColor(arrow); ctx.setFillColor(arrow)
ctx.setLineWidth(6); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 262, y: ay)); ctx.addLine(to: CGPoint(x: 398, y: ay)); ctx.strokePath()
ctx.move(to: CGPoint(x: 412, y: ay))            // arrowhead pointing right
ctx.addLine(to: CGPoint(x: 388, y: ay + 13))
ctx.addLine(to: CGPoint(x: 388, y: ay - 13))
ctx.closePath(); ctx.fillPath()

// Title text near the top.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = ns
let para = NSMutableParagraphStyle(); para.alignment = .center
let title = NSAttributedString(string: "Drag CallTape to Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
    .paragraphStyle: para,
])
let tw = title.size().width
title.draw(at: NSPoint(x: (CGFloat(W) - tw) / 2, y: CGFloat(H) - 66))

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: out))
