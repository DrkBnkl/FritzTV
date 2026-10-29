#!/usr/bin/env swift
// Erzeugt urheberrechtlich unbedenkliche Beispiel-Screenshots (1600×900, 16:9)
// für die GitHub-README in `docs/screenshots/` direkt mit SwiftUI & ImageRenderer.
// Aufruf aus dem Projektordner:  swift scripts/make-screenshots.swift

import AppKit
import SwiftUI

let width: CGFloat = 1600
let height: CGFloat = 900

let uiText = Color(red: 0.95, green: 0.96, blue: 0.97)
let uiSecondary = Color(red: 0.66, green: 0.69, blue: 0.74)
let uiPanel = Color(red: 0.04, green: 0.08, blue: 0.15).opacity(0.92)
let uiAccent = Color(red: 0.50, green: 0.78, blue: 1.0)
let epgTile = Color(red: 0.08, green: 0.12, blue: 0.19).opacity(0.92)
let epgTilePast = Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.75)
let epgTileSelected = Color(red: 0.16, green: 0.28, blue: 0.46)
let nowRed = Color(red: 1.0, green: 0.38, blue: 0.35)
let liveGreen = Color(red: 0.30, green: 0.85, blue: 0.45)
let timeshiftOrange = Color(red: 1.0, green: 0.65, blue: 0.18)

/// Weichgezeichneter, urheberrechtsfreier Landschafts-Hintergrund (Alpen-Abendstimmung) als TV-Bild.
struct ScenicTVBackground: View {
    var darken: Double = 0.18
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.18, blue: 0.36),
                    Color(red: 0.24, green: 0.42, blue: 0.56),
                    Color(red: 0.68, green: 0.50, blue: 0.44),
                    Color(red: 0.14, green: 0.26, blue: 0.34),
                    Color(red: 0.06, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.95, green: 0.68, blue: 0.38).opacity(0.35))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: 260, y: -120)
            Circle()
                .fill(Color(red: 0.20, green: 0.58, blue: 0.78).opacity(0.28))
                .frame(width: 640, height: 420)
                .blur(radius: 100)
                .offset(x: -280, y: 160)
            Color.black.opacity(darken)
        }
    }
}

struct BadgePill: View {
    let text: String
    var fg: Color = uiAccent
    var bg: Color = uiAccent.opacity(0.16)
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct ChannelEmblem: View {
    let short: String
    var width: CGFloat = 48
    var height: CGFloat = 34

    var body: some View {
        Text(short)
            .font(.system(size: short.count <= 3 ? 13 : 11, weight: .heavy, design: .rounded))
            .foregroundStyle(uiText)
            .frame(width: width, height: height)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - 1. EPG-Zeitstrahl
struct EPGScreenshotView: View {
    struct Prog {
        let start: Int // Minuten ab 19:00
        let end: Int
        let title: String
        let past: Bool
    }
    struct Row {
        let num: Int
        let name: String
        let short: String
        let selected: Bool
        let progs: [Prog]
    }

    let rows: [Row] = [
        Row(num: 1, name: "Das Erste HD", short: "ARD", selected: false, progs: [
            Prog(start: 0, end: 60, title: "Sportschau am Abend", past: true),
            Prog(start: 60, end: 75, title: "Tagesschau", past: true),
            Prog(start: 75, end: 165, title: "Das Gipfeltreffen – Naturdoku", past: false),
            Prog(start: 165, end: 200, title: "Tagesthemen", past: false),
            Prog(start: 200, end: 240, title: "maischberger", past: false)
        ]),
        Row(num: 2, name: "ZDF HD", short: "ZDF", selected: true, progs: [
            Prog(start: 0, end: 60, title: "heute · Wetter", past: true),
            Prog(start: 60, end: 75, title: "ZDF spezial", past: true),
            Prog(start: 75, end: 165, title: "Terra X: Wunder der Erde – Die Alpen", past: false),
            Prog(start: 165, end: 195, title: "heute journal", past: false),
            Prog(start: 195, end: 240, title: "auslandsjournal", past: false)
        ]),
        Row(num: 3, name: "3sat HD", short: "3sat", selected: false, progs: [
            Prog(start: 0, end: 60, title: "nano – Die Welt von morgen", past: true),
            Prog(start: 60, end: 75, title: "heute", past: true),
            Prog(start: 75, end: 135, title: "Kulturzeit Spezial: Architektur", past: false),
            Prog(start: 135, end: 195, title: "Dokumentarfilm: Wege durchs Eis", past: false),
            Prog(start: 195, end: 240, title: "3sat Wissen", past: false)
        ]),
        Row(num: 4, name: "ARTE HD", short: "ARTE", selected: false, progs: [
            Prog(start: 0, end: 45, title: "ARTE Re: Europas Züge", past: true),
            Prog(start: 45, end: 75, title: "ARTE Journal", past: true),
            Prog(start: 75, end: 170, title: "Geheimnisse der Tiefsee (1/2)", past: false),
            Prog(start: 170, end: 240, title: "Geheimnisse der Tiefsee (2/2)", past: false)
        ]),
        Row(num: 5, name: "NDR FS HH HD", short: "NDR", selected: false, progs: [
            Prog(start: 0, end: 30, title: "DAS! Rote Sofa", past: true),
            Prog(start: 30, end: 60, title: "Hamburg Journal", past: true),
            Prog(start: 60, end: 75, title: "Tagesschau", past: true),
            Prog(start: 75, end: 165, title: "die nordstory: Küstenwache", past: false),
            Prog(start: 165, end: 240, title: "NDR Info Aktuell", past: false)
        ]),
        Row(num: 6, name: "WDR Köln HD", short: "WDR", selected: false, progs: [
            Prog(start: 0, end: 30, title: "Aktuelle Stunde", past: true),
            Prog(start: 30, end: 60, title: "Lokalzeit aus Köln", past: true),
            Prog(start: 60, end: 75, title: "Tagesschau", past: true),
            Prog(start: 75, end: 165, title: "Abenteuer Erde: Unsere Wälder", past: false),
            Prog(start: 165, end: 240, title: "WDR aktuell", past: false)
        ]),
        Row(num: 7, name: "BR Fernsehen HD", short: "BR", selected: false, progs: [
            Prog(start: 0, end: 60, title: "Abendschau", past: true),
            Prog(start: 60, end: 75, title: "Tagesschau", past: true),
            Prog(start: 75, end: 165, title: "Quer – durch die Woche", past: false),
            Prog(start: 165, end: 240, title: "BR24 Rundschau", past: false)
        ]),
        Row(num: 8, name: "phoenix HD", short: "PHX", selected: false, progs: [
            Prog(start: 0, end: 75, title: "phoenix der tag", past: true),
            Prog(start: 75, end: 165, title: "phoenix runde: Energiewende", past: false),
            Prog(start: 165, end: 240, title: "heute journal", past: false)
        ]),
        Row(num: 9, name: "tagesschau24 HD", short: "TS24", selected: false, progs: [
            Prog(start: 0, end: 60, title: "Nachrichten im Überblick", past: true),
            Prog(start: 60, end: 75, title: "Tagesschau", past: true),
            Prog(start: 75, end: 150, title: "Wirtschaft & Wissen", past: false),
            Prog(start: 150, end: 240, title: "Tagesschau-Nachrichten", past: false)
        ])
    ]

    let ppm: CGFloat = 6.1
    let colW: CGFloat = 252
    let nowMins: Int = 102 // 20:42 Uhr

    var body: some View {
        VStack(spacing: 0) {
            // Kopfbereich mit Mini-Live-Vorschau links & Sendungsdetails rechts
            HStack(alignment: .top, spacing: 26) {
                ZStack(alignment: .topLeading) {
                    ScenicTVBackground(darken: 0.05)
                        .frame(width: 376, height: 212)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(uiAccent, lineWidth: 2)
                        )
                    HStack(spacing: 6) {
                        Circle().fill(liveGreen).frame(width: 8, height: 8)
                        Text("1 · Das Erste HD")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(uiText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Programmübersicht")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(uiAccent)
                        Spacer()
                        Text("Donnerstag, 29. Oktober · 20:42 Uhr")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(uiSecondary)
                    }
                    HStack(spacing: 10) {
                        Text("2 · ZDF HD")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(uiSecondary)
                        BadgePill(text: "JETZT", fg: Color(red: 0.04, green: 0.08, blue: 0.14), bg: uiAccent, size: 12)
                        BadgePill(text: "20:15 – 21:45 · noch 63 Min.", fg: uiSecondary, bg: Color.white.opacity(0.09), size: 12)
                    }
                    Text("Terra X: Wunder der Erde – Die Alpen von oben")
                        .font(.system(size: 27, weight: .heavy))
                        .foregroundStyle(uiText)
                    Text("Dokumentationsreihe · Deutschland 2026 · Dolby Digital 5.1")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(uiAccent)
                    Text("Vom Mont Blanc bis zum Großglockner: Spektakuläre Luftaufnahmen zeigen das empfindliche Ökosystem der Alpen im Wandel der Jahreszeiten und begleiten Forscher im Hochgebirge.")
                        .font(.system(size: 15))
                        .foregroundStyle(uiSecondary)
                        .lineLimit(2)

                    Spacer(minLength: 4)
                    HStack(spacing: 18) {
                        hintItem("Hoch/Runter", "Sender")
                        hintItem("Links/Rechts", "Zeit (-6 Std. bis +24 Std.)")
                        hintItem("Klick", "Umschalten / Details")
                        hintItem("Play/Pause", "Von Anfang an & Mediathek")
                        hintItem("Zurück", "Live-TV")
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .frame(height: 248)
            .background(Color(red: 0.03, green: 0.05, blue: 0.09))

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

            // Zeitleiste (Ruler) + Sender-Zeilen
            ZStack(alignment: .topLeading) {
                Color(red: 0.03, green: 0.05, blue: 0.09)

                VStack(spacing: 0) {
                    // Ruler
                    HStack(spacing: 0) {
                        Text("Sender")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(uiSecondary)
                            .padding(.leading, 22)
                            .frame(width: colW, alignment: .leading)
                        ZStack(alignment: .leading) {
                            ForEach([0, 30, 60, 90, 120, 150, 180], id: \.self) { mins in
                                let label = String(format: "%02d:%02d", 19 + mins / 60, mins % 60)
                                Text(label)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(uiSecondary)
                                    .offset(x: CGFloat(mins) * ppm + 6)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 38)
                    .background(Color(red: 0.05, green: 0.08, blue: 0.13))

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                    // Zeilen
                    VStack(spacing: 4) {
                        ForEach(rows, id: \.num) { row in
                            HStack(spacing: 0) {
                                // Linke Senderspalte
                                HStack(spacing: 10) {
                                    Text("\(row.num)")
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundStyle(row.selected ? uiAccent : uiSecondary)
                                        .frame(width: 24, alignment: .trailing)
                                    ChannelEmblem(short: row.short, width: 46, height: 32)
                                    Text(row.name)
                                        .font(.system(size: 15, weight: row.selected ? .bold : .medium))
                                        .foregroundStyle(uiText)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .frame(width: colW, height: 62)
                                .background(row.selected ? Color(red: 0.11, green: 0.19, blue: 0.31) : Color(red: 0.05, green: 0.08, blue: 0.13))
                                .overlay(alignment: .leading) {
                                    if row.selected {
                                        Rectangle().fill(uiAccent).frame(width: 4)
                                    }
                                }

                                // Kacheln im Zeitstrahl
                                ZStack(alignment: .leading) {
                                    ForEach(Array(row.progs.enumerated()), id: \.offset) { _, p in
                                        let x0 = CGFloat(p.start) * ppm + 2
                                        let w = max(20, CGFloat(p.end - p.start) * ppm - 4)
                                        let isRunning = p.start <= nowMins && nowMins < p.end
                                        let isFocused = row.selected && isRunning
                                        let tStr = String(format: "%02d:%02d – %02d:%02d",
                                                          19 + p.start / 60, p.start % 60,
                                                          19 + p.end / 60, p.end % 60)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(p.title)
                                                .font(.system(size: 15, weight: isRunning ? .bold : .medium))
                                                .foregroundStyle(p.past ? uiSecondary.opacity(0.75) : uiText)
                                                .lineLimit(1)
                                            Text(tStr)
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                .foregroundStyle(p.past ? uiSecondary.opacity(0.55) : uiSecondary)
                                            Spacer(minLength: 0)
                                            if isRunning {
                                                GeometryReader { geo in
                                                    let ratio = CGFloat(nowMins - p.start) / CGFloat(max(1, p.end - p.start))
                                                    ZStack(alignment: .leading) {
                                                        Capsule().fill(Color.white.opacity(0.16)).frame(height: 3)
                                                        Capsule().fill(uiAccent).frame(width: geo.size.width * ratio, height: 3)
                                                    }
                                                }
                                                .frame(height: 3)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(width: w, height: 60, alignment: .topLeading)
                                        .background(
                                            isFocused ? epgTileSelected : (p.past ? epgTilePast : epgTile),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(
                                                    isFocused ? uiAccent : (isRunning ? uiAccent.opacity(0.45) : Color.white.opacity(0.10)),
                                                    lineWidth: isFocused ? 2 : 1
                                                )
                                        )
                                        .offset(x: x0)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: 62, alignment: .leading)
                                .clipped()
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                // Rote „Jetzt“-Linie
                let nowX = colW + CGFloat(nowMins) * ppm
                Circle()
                    .fill(nowRed)
                    .frame(width: 10, height: 10)
                    .offset(x: nowX - 5, y: 14)
                Rectangle()
                    .fill(nowRed)
                    .frame(width: 2, height: height - 248 - 18)
                    .offset(x: nowX - 1, y: 18)
            }
        }
        .frame(width: width, height: height)
    }

    private func hintItem(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            BadgePill(text: key, fg: uiText, bg: Color.white.opacity(0.12), size: 12)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(uiSecondary)
        }
    }
}

// MARK: - 2. Live-TV mit Senderliste & InfoBanner
struct ChannelListScreenshotView: View {
    struct Entry {
        let num: Int
        let name: String
        let short: String
        let prog: String
        let ratio: CGFloat
        let selected: Bool
    }

    let entries: [Entry] = [
        Entry(num: 1, name: "Das Erste", short: "ARD", prog: "Tagesschau", ratio: 0.75, selected: true),
        Entry(num: 2, name: "ZDF", short: "ZDF", prog: "Terra X: Wunder der Erde", ratio: 0.25, selected: false),
        Entry(num: 3, name: "3sat", short: "3sat", prog: "Kulturzeit Spezial", ratio: 0.32, selected: false),
        Entry(num: 4, name: "ARTE", short: "ARTE", prog: "Geheimnisse der Tiefsee", ratio: 0.22, selected: false),
        Entry(num: 5, name: "NDR FS HH", short: "NDR", prog: "die nordstory: Küstenwache", ratio: 0.32, selected: false),
        Entry(num: 6, name: "WDR Köln", short: "WDR", prog: "Abenteuer Erde", ratio: 0.40, selected: false),
        Entry(num: 7, name: "SWR BW", short: "SWR", prog: "Marktcheck", ratio: 0.40, selected: false),
        Entry(num: 8, name: "BR Fernsehen", short: "BR", prog: "Quer – durch die Woche", ratio: 0.40, selected: false),
        Entry(num: 9, name: "hr-fernsehen", short: "HR", prog: "Alles Wissen", ratio: 0.40, selected: false),
        Entry(num: 10, name: "phoenix", short: "PHX", prog: "phoenix runde", ratio: 0.40, selected: false)
    ]

    var body: some View {
        ZStack {
            ScenicTVBackground(darken: 0.14)

            HStack(alignment: .bottom, spacing: 28) {
                // Linke Senderliste
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(uiAccent)
                        Text("Programmübersicht")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(uiText)
                        Spacer()
                        Text("Zeitstrahl →")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(uiAccent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(epgTileSelected.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(uiAccent.opacity(0.5), lineWidth: 1)
                    )

                    Text("Senderliste · 84 Kabelsender")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(uiSecondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 6) {
                        ForEach(entries, id: \.num) { item in
                            HStack(spacing: 12) {
                                Text("\(item.num)")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(item.selected ? uiAccent : uiSecondary)
                                    .frame(width: 26, alignment: .trailing)
                                ChannelEmblem(short: item.short, width: 46, height: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.name)
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(uiText)
                                        Spacer()
                                        BadgePill(text: "HD", size: 11)
                                    }
                                    HStack(spacing: 10) {
                                        Text(item.prog)
                                            .font(.system(size: 14))
                                            .foregroundStyle(uiSecondary)
                                            .lineLimit(1)
                                        Spacer()
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.16)).frame(width: 96, height: 4)
                                            Capsule().fill(uiAccent).frame(width: 96 * item.ratio, height: 4)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                item.selected ? epgTileSelected : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(item.selected ? uiAccent : Color.clear, lineWidth: 2)
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(width: 490, height: height - 56)
                .background(uiPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

                // Rechts unten: InfoBanner
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Text("1")
                            .font(.system(size: 34, weight: .heavy, design: .monospaced))
                            .foregroundStyle(uiAccent)
                        ChannelEmblem(short: "ARD", width: 56, height: 38)
                        Text("Das Erste")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(uiText)
                        BadgePill(text: "HD", size: 13)
                        BadgePill(text: "LIVE", fg: Color(red: 0.04, green: 0.12, blue: 0.06), bg: liveGreen, size: 13)
                        Spacer()
                        Text("20:11 Uhr")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(uiSecondary)
                    }

                    HStack(spacing: 12) {
                        Text("20:00 – 20:15")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(uiAccent)
                        Text("Tagesschau")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(uiText)
                        Text("·  Die Nachrichten der ARD")
                            .font(.system(size: 16))
                            .foregroundStyle(uiSecondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18)).frame(height: 6)
                            Capsule().fill(uiAccent).frame(width: geo.size.width * 0.75, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 12) {
                        Text("Danach  20:15")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(uiSecondary)
                        Text("Das Gipfeltreffen – Naturdokumentation")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(uiSecondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(uiPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
            .padding(28)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - 3. Sendungsinfo (InfoPanel) + TimeshiftBar
struct InfoPanelTimeshiftScreenshotView: View {
    let pills: [(String, String, Bool)] = [
        ("clock.arrow.circlepath", "Von Anfang an", true),
        ("magnifyingglass", "In Mediathek suchen", false),
        ("speaker.wave.2.fill", "Ton: Deutsch (Dolby Digital 5.1)", false),
        ("captions.bubble", "Untertitel: DVB (Deutsch)", false),
        ("gearshape", "Einstellungen…", false),
        ("list.bullet", "Senderliste", false)
    ]

    var body: some View {
        ZStack {
            ScenicTVBackground(darken: 0.16)

            VStack {
                // Oben: InfoPanel
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Text("2")
                            .font(.system(size: 34, weight: .heavy, design: .monospaced))
                            .foregroundStyle(uiAccent)
                        ChannelEmblem(short: "ZDF", width: 56, height: 38)
                        Text("ZDF")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(uiText)
                        BadgePill(text: "HD", size: 13)
                        BadgePill(text: "TIMESHIFT · -12:40", fg: Color(red: 0.12, green: 0.06, blue: 0.0), bg: timeshiftOrange, size: 13)
                        Spacer()
                        Text("1080p50 · Dolby Digital 5.1")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(uiSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Terra X: Wunder der Erde – Die Alpen von oben")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(uiText)
                        Text("20:15 – 21:45  ·  Dokumentationsreihe (Deutschland 2026)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(uiAccent)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18)).frame(height: 6)
                            Capsule().fill(uiAccent).frame(width: geo.size.width * 0.34, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("Spektakuläre Luftaufnahmen zeigen das empfindliche Ökosystem der Alpen im Wandel der Jahreszeiten. Gletscherforscher und Biologen berichten von den höchsten Gipfeln zwischen Mont Blanc und Zugspitze.")
                        .font(.system(size: 16))
                        .foregroundStyle(uiSecondary)
                        .lineSpacing(3)

                    HStack(spacing: 12) {
                        ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                            HStack(spacing: 8) {
                                Image(systemName: pill.0)
                                    .font(.system(size: 14, weight: .bold))
                                Text(pill.1)
                                    .font(.system(size: 15, weight: pill.2 ? .bold : .semibold))
                            }
                            .foregroundStyle(pill.2 ? Color(red: 0.04, green: 0.08, blue: 0.14) : uiText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                pill.2 ? uiAccent : Color.white.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(26)
                .background(uiPanel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

                Spacer()

                // Unten: TimeshiftBar
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        BadgePill(text: "❚❚  PAUSE", fg: Color(red: 0.12, green: 0.06, blue: 0.0), bg: timeshiftOrange, size: 14)
                        Text("2 · ZDF HD")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(uiText)
                        Text("·  Terra X: Wunder der Erde – Die Alpen von oben")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(uiSecondary)
                        Spacer()
                        Text("-12:40 Min. hinter Live")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(timeshiftOrange)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14)).frame(height: 10)
                            Capsule().fill(Color.white.opacity(0.32)).frame(width: geo.size.width * 0.72, height: 10)
                            Capsule().fill(timeshiftOrange).frame(width: geo.size.width * 0.54, height: 10)
                            Circle()
                                .fill(uiText)
                                .frame(width: 16, height: 16)
                                .offset(x: geo.size.width * 0.54 - 8)
                        }
                    }
                    .frame(height: 16)

                    HStack {
                        Text("Play/Pause: Weiterlaufen  ·  Links/Rechts: Spulen (10 s → 30 s → 1 Min. → 3 Min. → 5 Min.)  ·  Hoch/Runter: Live & Senderwechsel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(uiSecondary)
                        Spacer()
                        Text("Puffer: 38 Min. / 90 Min.")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(uiSecondary)
                    }
                }
                .padding(24)
                .background(uiPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
            .padding(36)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - 4. Mediathek-Suche („Sendung verpasst“)
struct MediathekScreenshotView: View {
    struct Item {
        let channel: String
        let topic: String
        let title: String
        let date: String
        let duration: String
        let hd: Bool
        let ut: Bool
        let desc: String
        let selected: Bool
    }

    let items: [Item] = [
        Item(channel: "ZDF", topic: "Terra X", title: "Wunder der Erde – Die Alpen von oben",
             date: "29.10.2026 · 20:15 Uhr", duration: "44 Min.", hd: true, ut: true,
             desc: "Vom Mont Blanc bis zum Großglockner: Spektakuläre Luftaufnahmen zeigen das empfindliche Ökosystem der Alpen im Wandel der Jahreszeiten.",
             selected: true),
        Item(channel: "ZDF", topic: "Terra X", title: "Wunder der Erde – Skandinaviens wilder Norden",
             date: "22.10.2026 · 19:30 Uhr", duration: "43 Min.", hd: true, ut: true,
             desc: "Zwischen Fjorden, Gletschern und Polarlichtern: Eine Reise durch die unberührten Nationalparks Norwegens und Schwedens.",
             selected: false),
        Item(channel: "3sat", topic: "Terra X", title: "Wunder der Erde – Unsere Meere im Wandel",
             date: "18.10.2026 · 20:15 Uhr", duration: "45 Min.", hd: true, ut: true,
             desc: "Meeresbiologen erforschen die Korallenriffe und Kelpwälder der Weltmeere und zeigen überraschende Anpassungsstrategien.",
             selected: false),
        Item(channel: "ZDFinfo", topic: "Terra X", title: "Wunder der Erde – Vulkane und Geysire auf Island",
             date: "11.10.2026 · 21:00 Uhr", duration: "44 Min.", hd: true, ut: true,
             desc: "Wo Feuer und Eis aufeinandertreffen: Geologen begleiten die jüngsten vulkanischen Aktivitäten auf der Reykjanes-Halbinsel.",
             selected: false),
        Item(channel: "ARTE", topic: "Entdeckung", title: "Die Alpen – Gipfelstürmer und Gletscherwelten",
             date: "04.10.2026 · 20:15 Uhr", duration: "52 Min.", hd: true, ut: false,
             desc: "Dokumentation über den hochalpinen Lebensraum und die Auswirkungen des Klimawandels auf die europäischen Gebirgsflüsse.",
             selected: false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In der Mediathek gefunden")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(uiText)
                    Text("Suchbegriff: „Terra X: Wunder der Erde“  ·  5 passende Sendungen (MediathekViewWeb)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(uiSecondary)
                }
                Spacer()
                Text("Schließen")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(uiText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            BadgePill(text: item.channel, fg: Color(red: 0.04, green: 0.08, blue: 0.14), bg: uiAccent, size: 13)
                            Text("\(item.topic)  ·  \(item.date)  ·  \(item.duration)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(uiSecondary)
                            Spacer()
                            if item.hd {
                                BadgePill(text: "HD", size: 12)
                            }
                            if item.ut {
                                BadgePill(text: "UT", fg: uiText, bg: Color.white.opacity(0.14), size: 12)
                            }
                        }
                        Text(item.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(uiText)
                        Text(item.desc)
                            .font(.system(size: 15))
                            .foregroundStyle(uiSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(
                        item.selected ? epgTileSelected : epgTile,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(item.selected ? uiAccent : Color.white.opacity(0.10), lineWidth: item.selected ? 2 : 1)
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 42)
        .frame(width: width, height: height)
        .background(Color(red: 0.04, green: 0.07, blue: 0.12))
    }
}

@MainActor
func save<V: View>(_ view: V, to filename: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    guard let cgImage = renderer.cgImage else {
        fputs("Fehler beim Rendern von \(filename)\n", stderr)
        return
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/screenshots")
        .appendingPathComponent(filename)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url)
    print("✔ Gespeichert:", url.path)
}

MainActor.assumeIsolated {
    save(EPGScreenshotView(), to: "epg-zeitstrahl.png")
    save(ChannelListScreenshotView(), to: "senderliste-live.png")
    save(InfoPanelTimeshiftScreenshotView(), to: "sendungsinfo-timeshift.png")
    save(MediathekScreenshotView(), to: "mediathek-suche.png")
}
