#!/usr/bin/env swift
import AppKit
import Foundation

// MARK: - Script zur Erzeugung hochauflösender Apple TV Top Shelf Kacheln
// Erzeugt gestochen scharfe 616x616 (@2x) und 308x308 (@1x) Icons für die
// wichtigsten TV-Sender sowie ein generisches Fallback-Icon im FritzTV-Design.

struct ChannelConfig {
    let slug: String
    let displayName: String
    let isHD: Bool
    let accentColor: NSColor
    let altSlugs: [String]

    init(slug: String, displayName: String, isHD: Bool = true, accent: NSColor, altSlugs: [String] = []) {
        self.slug = slug
        self.displayName = displayName
        self.isHD = isHD
        self.accentColor = accent
        self.altSlugs = altSlugs
    }
}

let channels: [ChannelConfig] = [
    // 12 Hauptsender (Top Shelf Standardbelegung)
    ChannelConfig(slug: "das_erste", displayName: "Das Erste HD", accent: NSColor(red: 0.18, green: 0.42, blue: 0.88, alpha: 1)),
    ChannelConfig(slug: "zdf", displayName: "ZDF HD", accent: NSColor(red: 0.96, green: 0.48, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "rbb_berlin", displayName: "rbb Berlin HD", accent: NSColor(red: 0.85, green: 0.12, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "arte", displayName: "arte HD", accent: NSColor(red: 0.95, green: 0.22, blue: 0.18, alpha: 1)),
    ChannelConfig(slug: "3sat", displayName: "3sat HD", accent: NSColor(red: 0.88, green: 0.10, blue: 0.22, alpha: 1)),
    ChannelConfig(slug: "phoenix", displayName: "phoenix HD", accent: NSColor(red: 0.05, green: 0.65, blue: 0.68, alpha: 1)),
    ChannelConfig(slug: "zdf_neo", displayName: "ZDFneo HD", accent: NSColor(red: 0.96, green: 0.48, blue: 0.05, alpha: 1), altSlugs: ["zdfneo"]),
    ChannelConfig(slug: "zdfinfo", displayName: "ZDFinfo HD", accent: NSColor(red: 0.96, green: 0.48, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "one", displayName: "ONE HD", accent: NSColor(red: 0.35, green: 0.20, blue: 0.70, alpha: 1)),
    ChannelConfig(slug: "tagesschau24", displayName: "tagesschau24 HD", accent: NSColor(red: 0.10, green: 0.35, blue: 0.75, alpha: 1)),
    ChannelConfig(slug: "kika", displayName: "KiKA HD", accent: NSColor(red: 0.20, green: 0.75, blue: 0.35, alpha: 1)),
    ChannelConfig(slug: "ard_alpha", displayName: "ARD-alpha HD", accent: NSColor(red: 0.85, green: 0.40, blue: 0.10, alpha: 1), altSlugs: ["ardalpha"]),

    // Dritte Programme
    ChannelConfig(slug: "rbb_brandenburg", displayName: "rbb Brandenb. HD", accent: NSColor(red: 0.85, green: 0.12, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "ndr_fs_nds", displayName: "NDR Fernsehen HD", accent: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1), altSlugs: ["ndr"]),
    ChannelConfig(slug: "mdr_sachsen", displayName: "MDR Fernsehen HD", accent: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1), altSlugs: ["mdr"]),
    ChannelConfig(slug: "wdr_koeln", displayName: "WDR Fernsehen HD", accent: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1), altSlugs: ["wdr_koln", "wdr"]),
    ChannelConfig(slug: "br_sued", displayName: "BR Fernsehen HD", accent: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1), altSlugs: ["br_sud", "br"]),
    ChannelConfig(slug: "hr_fernsehen", displayName: "hr-fernsehen HD", accent: NSColor(red: 0.85, green: 0.40, blue: 0.10, alpha: 1), altSlugs: ["hr-fernsehen", "hr"]),
    ChannelConfig(slug: "swr_rp", displayName: "SWR Fernsehen HD", accent: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1), altSlugs: ["swr"]),
    ChannelConfig(slug: "sr_fernsehen", displayName: "SR Fernsehen HD", accent: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1), altSlugs: ["sr"]),

    // Beliebte Privatsender
    ChannelConfig(slug: "rtl", displayName: "RTL", accent: NSColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "sat1", displayName: "SAT.1", accent: NSColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1), altSlugs: ["sat.1"]),
    ChannelConfig(slug: "prosieben", displayName: "ProSieben", accent: NSColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)),
    ChannelConfig(slug: "vox", displayName: "VOX", accent: NSColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "kabel_eins", displayName: "kabel eins", accent: NSColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "rtlzwei", displayName: "RTLZWEI", accent: NSColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1), altSlugs: ["rtl2"]),
    ChannelConfig(slug: "super_rtl", displayName: "SUPER RTL", accent: NSColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "ntv", displayName: "ntv", accent: NSColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)),
    ChannelConfig(slug: "welt", displayName: "WELT", accent: NSColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 1)),
    ChannelConfig(slug: "nitro", displayName: "NITRO", accent: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "sixx", displayName: "SIXX", accent: NSColor(red: 0.85, green: 0.30, blue: 0.55, alpha: 1)),
    ChannelConfig(slug: "tele_5", displayName: "TELE 5", accent: NSColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1)),
    ChannelConfig(slug: "dmax", displayName: "DMAX", accent: NSColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "tlc", displayName: "TLC", accent: NSColor(red: 0.85, green: 0.20, blue: 0.35, alpha: 1)),
    ChannelConfig(slug: "sport1", displayName: "SPORT1", accent: NSColor(red: 0.90, green: 0.45, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "eurosport_1", displayName: "Eurosport 1", accent: NSColor(red: 0.10, green: 0.25, blue: 0.60, alpha: 1)),
    ChannelConfig(slug: "prosieben_maxx", displayName: "Pro7 MAXX", accent: NSColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1)),
    ChannelConfig(slug: "sat1_gold", displayName: "SAT.1 Gold", accent: NSColor(red: 0.85, green: 0.65, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "kabel_eins_doku", displayName: "kabel eins Doku", accent: NSColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "n24_doku", displayName: "N24 DOKU", accent: NSColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1)),
    ChannelConfig(slug: "rtlup", displayName: "RTLup", accent: NSColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "voxup", displayName: "VOXup", accent: NSColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)),
    ChannelConfig(slug: "comedy_central", displayName: "Comedy Central", accent: NSColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "mtv", displayName: "MTV", accent: NSColor(red: 0.95, green: 0.85, blue: 0.10, alpha: 1)),
    ChannelConfig(slug: "disney_channel", displayName: "Disney Channel", accent: NSColor(red: 0.10, green: 0.45, blue: 0.85, alpha: 1)),
    ChannelConfig(slug: "nick", displayName: "Nick", accent: NSColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1)),
    ChannelConfig(slug: "toggo_plus", displayName: "TOGGO plus", accent: NSColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1))
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let projectRoot = URL(fileURLWithPath: scriptDir).deletingLastPathComponent().path
let outputDir = "\(projectRoot)/App/TopShelf/Resources"
let cacheDir = "/tmp/fritztv_logo_cache"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

func fetchLogo(slug: String) -> NSImage? {
    let localCache = "\(cacheDir)/\(slug).png"
    if FileManager.default.fileExists(atPath: localCache), let img = NSImage(contentsOfFile: localCache) {
        return img
    }
    guard let url = URL(string: "http://tv.avm.de/tvapp/logos/\(slug).png") else { return nil }
    var req = URLRequest(url: url)
    req.setValue("FritzTV/1.0", forHTTPHeaderField: "User-Agent")
    
    let sema = DispatchSemaphore(value: 0)
    var resultImage: NSImage? = nil
    
    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sema.signal() }
        if let data = data, let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
            try? data.write(to: URL(fileURLWithPath: localCache))
            resultImage = NSImage(data: data)
        }
    }.resume()
    
    sema.wait()
    return resultImage
}

func renderTile(size: CGSize, scale: CGFloat, channel: ChannelConfig?, isGeneric: Bool = false) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    
    let s = scale
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let accent = channel?.accentColor ?? NSColor(red: 0.22, green: 0.55, blue: 0.98, alpha: 1.0)
    
    // 1. Hintergrundverlauf (modernes dunkles Slate/Graphite)
    let bgColors = [
        NSColor(red: 0.13, green: 0.16, blue: 0.24, alpha: 1.0).cgColor,
        NSColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1.0).cgColor
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    
    let cardRect = CGRect(origin: .zero, size: size)
    let cornerRadius: CGFloat = 42 * s
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    cg.addPath(cardPath)
    cg.clip()
    cg.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
    
    // 2. Akzentschein in der Senderfarbe (unten rechts)
    cg.saveGState()
    let glowCenter = CGPoint(x: size.width * 0.80, y: size.height * 0.20)
    let glowColors = [accent.withAlphaComponent(0.28).cgColor, accent.withAlphaComponent(0.0).cgColor] as CFArray
    let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
    cg.drawRadialGradient(glowGrad, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: size.width * 0.65, options: [])
    cg.restoreGState()
    
    // 3. Subtile innere Lichtkante
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    cg.setLineWidth(1.5 * s)
    cg.addPath(cardPath)
    cg.strokePath()
    
    // 4. HD-Badge oben rechts
    if let ch = channel, ch.isHD {
        let hdW: CGFloat = 66 * s
        let hdH: CGFloat = 40 * s
        let hdRect = CGRect(x: size.width - (22 * s) - hdW, y: size.height - (22 * s) - hdH, width: hdW, height: hdH)
        let hdPath = CGPath(roundedRect: hdRect, cornerWidth: 10 * s, cornerHeight: 10 * s, transform: nil)
        cg.setFillColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        cg.addPath(hdPath)
        cg.fillPath()
        
        let hdStr = "HD" as NSString
        let hdFont = NSFont.systemFont(ofSize: 20 * s, weight: .bold)
        let hdAttrs: [NSAttributedString.Key: Any] = [
            .font: hdFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let hdSize = hdStr.size(withAttributes: hdAttrs)
        let hdPoint = CGPoint(x: hdRect.midX - hdSize.width / 2, y: hdRect.midY - hdSize.height / 2)
        hdStr.draw(at: hdPoint, withAttributes: hdAttrs)
    }
    
    // 5. Zentrierte Logokarte (weißes Badge für perfekten Kontrast aller Senderlogos)
    let plateW: CGFloat = 226 * s
    let plateH: CGFloat = 126 * s
    let plateRect = CGRect(x: (size.width - plateW) / 2, y: (size.height - plateH) / 2 + (12 * s), width: plateW, height: plateH)
    let platePath = CGPath(roundedRect: plateRect, cornerWidth: 18 * s, cornerHeight: 18 * s, transform: nil)
    
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -3 * s), blur: 10 * s, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    cg.setFillColor(NSColor.white.cgColor)
    cg.addPath(platePath)
    cg.fillPath()
    cg.restoreGState()
    
    // Logo auf der Kachel
    if let ch = channel, let logo = fetchLogo(slug: ch.slug) {
        let logoSize = logo.size
        let maxW = plateW - (32 * s)
        let maxH = plateH - (22 * s)
        let scaleFactor = min(maxW / logoSize.width, maxH / logoSize.height)
        let drawW = logoSize.width * scaleFactor
        let drawH = logoSize.height * scaleFactor
        let drawRect = CGRect(
            x: plateRect.midX - drawW / 2,
            y: plateRect.midY - drawH / 2,
            width: drawW,
            height: drawH
        )
        logo.draw(in: drawRect)
    } else {
        // Generisches Symbol: FritzTV Play-Dreieck / Welle
        let triPath = CGMutablePath()
        let triCenter = CGPoint(x: plateRect.midX + (3 * s), y: plateRect.midY)
        let triRadius: CGFloat = 28 * s
        triPath.move(to: CGPoint(x: triCenter.x - triRadius * 0.7, y: triCenter.y - triRadius))
        triPath.addLine(to: CGPoint(x: triCenter.x + triRadius * 0.9, y: triCenter.y))
        triPath.addLine(to: CGPoint(x: triCenter.x - triRadius * 0.7, y: triCenter.y + triRadius))
        triPath.closeSubpath()
        
        cg.setFillColor(accent.cgColor)
        cg.addPath(triPath)
        cg.fillPath()
    }
    
    // 6. Sendername am unteren Rand
    let titleStr = (channel?.displayName ?? "FritzTV") as NSString
    let titleFont = NSFont.systemFont(ofSize: 18 * s, weight: .semibold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white
    ]
    let titleSize = titleStr.size(withAttributes: titleAttrs)
    let titlePoint = CGPoint(
        x: max(16 * s, (size.width - titleSize.width) / 2),
        y: 28 * s
    )
    titleStr.draw(at: titlePoint, withAttributes: titleAttrs)
    
    NSGraphicsContext.restoreGraphicsState()
    
    return rep.representation(using: .png, properties: [:])
}

print("Erzeuge Top Shelf Kacheln in \(outputDir)...")

for channel in channels {
    let slugsToGenerate = [channel.slug] + channel.altSlugs
    for slug in slugsToGenerate {
        let baseName = "channel_\(slug)"
        // 2x: 616x616
        if let d2x = renderTile(size: CGSize(width: 616, height: 616), scale: 2.0, channel: channel) {
            try? d2x.write(to: URL(fileURLWithPath: "\(outputDir)/\(baseName)@2x.png"))
        }
        // 1x: 308x308
        if let d1x = renderTile(size: CGSize(width: 308, height: 308), scale: 1.0, channel: channel) {
            try? d1x.write(to: URL(fileURLWithPath: "\(outputDir)/\(baseName).png"))
        }
    }
    print("✓ \(channel.displayName) (\(channel.slug))")
}

// Generisches Fallback-Icon
if let gen2x = renderTile(size: CGSize(width: 616, height: 616), scale: 2.0, channel: nil, isGeneric: true) {
    try? gen2x.write(to: URL(fileURLWithPath: "\(outputDir)/channel_generic@2x.png"))
}
if let gen1x = renderTile(size: CGSize(width: 308, height: 308), scale: 1.0, channel: nil, isGeneric: true) {
    try? gen1x.write(to: URL(fileURLWithPath: "\(outputDir)/channel_generic.png"))
}
print("✓ Generisches Fallback-Icon (channel_generic)")

print("\nFertig! Alle Kacheln erfolgreich in \(outputDir) erzeugt.")
