#!/usr/bin/env swift
// Erzeugt das App-Icon von FritzRadio im Stil von FritzTV: dunkelblaue Kachel, Radio mit
// Antenne und blauem Lautsprecher.
// Aufruf aus dem Projektordner:  swift scripts/make-radio-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let folder = root.appendingPathComponent("App/Radio/Assets.xcassets/AppIcon.appiconset")

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, _ rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// Zeichnet das Icon in 1024 × 1024 (Ursprung unten links).
func draw(_ ctx: CGContext) {
    // Kachel mit Rand wie die Mac-Icons von Apple
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(10, 12, 20))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(ctx, tilePath, rgb(36, 41, 76), rgb(10, 12, 20), tile)
    // warmer Schein unten rechts
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 58 / 255, green: 140 / 255, blue: 1, alpha: 0.35), CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 820, y: 180), startRadius: 0,
                           endCenter: CGPoint(x: 820, y: 180), endRadius: 520, options: [])
    ctx.restoreGState()

    // Antenne mit Funkwellen
    let antenna = rgb(205, 210, 228)
    ctx.setStrokeColor(antenna)
    ctx.setLineCap(.round)
    ctx.setLineWidth(22)
    ctx.move(to: CGPoint(x: 340, y: 600))
    ctx.addLine(to: CGPoint(x: 640, y: 790))
    ctx.strokePath()
    ctx.setFillColor(antenna)
    ctx.fillEllipse(in: CGRect(x: 622, y: 772, width: 36, height: 36))
    ctx.setStrokeColor(rgb(110, 185, 255))
    ctx.setLineWidth(18)
    for radius in [70.0, 115.0] {
        ctx.addArc(center: CGPoint(x: 640, y: 790), radius: radius, startAngle: -.pi / 9, endAngle: .pi / 2.6, clockwise: false)
        ctx.strokePath()
    }

    // Gehäuse
    let body = CGRect(x: 230, y: 270, width: 564, height: 350)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 64, cornerHeight: 64, transform: nil)
    fillGradient(ctx, bodyPath, rgb(70, 77, 110), rgb(36, 40, 60), body)
    let face = body.insetBy(dx: 26, dy: 26)
    let facePath = CGPath(roundedRect: face, cornerWidth: 42, cornerHeight: 42, transform: nil)
    fillGradient(ctx, facePath, rgb(24, 30, 52), rgb(9, 11, 19), face)

    // Lautsprecher in Akzentfarbe
    let speaker = CGRect(x: 290, y: 330, width: 230, height: 230)
    fillGradient(ctx, CGPath(ellipseIn: speaker, transform: nil), rgb(150, 212, 255), rgb(58, 140, 255), speaker)
    ctx.setStrokeColor(CGColor(red: 9 / 255, green: 11 / 255, blue: 19 / 255, alpha: 0.55))
    ctx.setLineWidth(10)
    for inset in [40.0, 78.0] {
        ctx.strokeEllipse(in: speaker.insetBy(dx: inset, dy: inset))
    }

    // Senderskala und Drehknopf
    ctx.setStrokeColor(antenna)
    ctx.setLineWidth(12)
    for (index, x) in stride(from: 570.0, through: 730.0, by: 32).enumerated() {
        let height: CGFloat = index % 2 == 0 ? 60 : 36
        ctx.move(to: CGPoint(x: x, y: 520 - height))
        ctx.addLine(to: CGPoint(x: x, y: 520))
        ctx.strokePath()
    }
    ctx.setStrokeColor(rgb(255, 120, 90))
    ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: 650, y: 445))
    ctx.addLine(to: CGPoint(x: 650, y: 535))
    ctx.strokePath()
    let knob = CGRect(x: 610, y: 330, width: 80, height: 80)
    fillGradient(ctx, CGPath(ellipseIn: knob, transform: nil), rgb(205, 210, 228), rgb(120, 126, 150), knob)
}

let master = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
draw(NSGraphicsContext.current!.cgContext)
NSGraphicsContext.restoreGraphicsState()
let masterImage = master.cgImage!

try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let data = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        try data.write(to: folder.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("✔ Icon geschrieben: \(folder.path)")
