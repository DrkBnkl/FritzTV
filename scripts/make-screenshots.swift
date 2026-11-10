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
                        Text("Freitag, 30. Oktober · 20:42 Uhr")
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

// MARK: - Maße wie in der App (tvOS, 1920 × 1080), auf 1600 × 900 umgerechnet
let tvScale: CGFloat = width / 1920
func s(_ value: CGFloat) -> CGFloat { value * tvScale }
func tvFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size * tvScale, weight: weight) }
/// Sicherer Bereich des Apple TV (Ränder, die ein Fernseher nicht abschneidet).
let safeHorizontal: CGFloat = s(80)
let safeVertical: CGFloat = s(60)

/// Plakette wie `Badge` in der App (Umriss).
struct OutlineBadge: View {
    let text: String
    var dark = false
    var body: some View {
        Text(text)
            .font(tvFont(22, .bold))
            .foregroundStyle(dark ? Color.black : uiText)
            .padding(.horizontal, s(14))
            .padding(.vertical, s(4))
            .overlay(RoundedRectangle(cornerRadius: s(8)).stroke(dark ? Color.black : uiText, lineWidth: s(2)))
    }
}

/// Tafel wie `PanelBackground` (durchscheinend, heller Rand).
struct TVPanel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, s(48))
            .padding(.vertical, s(36))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(uiPanel, in: RoundedRectangle(cornerRadius: s(32), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: s(32), style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - 2. Senderliste mit Programmdetails (Zurück-Taste)
struct ChannelListScreenshotView: View {
    struct Entry {
        let num: Int
        let name: String
        let short: String
        let hd: Bool
        let time: String
        let prog: String
    }

    let recent = Entry(num: 2, name: "ZDF", short: "ZDF", hd: true, time: "20:15 – 21:45", prog: "Terra X: Wunder der Erde")
    let entries: [Entry] = [
        Entry(num: 1, name: "Das Erste", short: "ARD", hd: true, time: "20:15 – 21:45", prog: "Das Gipfeltreffen – Naturdoku"),
        Entry(num: 2, name: "ZDF", short: "ZDF", hd: true, time: "20:15 – 21:45", prog: "Terra X: Wunder der Erde"),
        Entry(num: 3, name: "3sat", short: "3sat", hd: true, time: "20:15 – 21:15", prog: "Kulturzeit Spezial: Architektur"),
        Entry(num: 4, name: "ARTE", short: "ARTE", hd: true, time: "20:15 – 21:50", prog: "Geheimnisse der Tiefsee (1/2)"),
        Entry(num: 5, name: "NDR FS HH", short: "NDR", hd: true, time: "20:15 – 21:45", prog: "die nordstory: Küstenwache"),
        Entry(num: 6, name: "WDR Köln", short: "WDR", hd: true, time: "20:15 – 21:45", prog: "Abenteuer Erde: Unsere Wälder"),
        Entry(num: 7, name: "BR Fernsehen", short: "BR", hd: true, time: "20:15 – 21:45", prog: "Quer – durch die Woche"),
        Entry(num: 8, name: "phoenix", short: "PHX", hd: true, time: "20:15 – 21:45", prog: "phoenix runde: Energiewende"),
        Entry(num: 9, name: "tagesschau24", short: "TS24", hd: true, time: "20:15 – 21:30", prog: "Wirtschaft & Wissen")
    ]
    let selectedNumber = 1
    let runningNumber = 2

    var body: some View {
        ZStack(alignment: .leading) {
            ScenicTVBackground(darken: 0.10)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: s(14)) {
                    VStack(alignment: .leading, spacing: s(6)) {
                        specialRow
                            .frame(height: s(58))
                        sectionHeader("ZULETZT GESEHEN", top: s(8))
                        row(recent, recentSection: true)
                        sectionHeader("ALLE SENDER", top: s(10))
                        ForEach(entries, id: \.num) { entry in
                            row(entry, recentSection: false)
                        }
                    }
                    .padding(.horizontal, s(20))
                    .padding(.vertical, s(8))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()

                    Text("Klick: umschalten · Zurück: schließen")
                        .font(tvFont(22))
                        .foregroundStyle(uiSecondary)
                        .padding(.horizontal, s(20))
                }
                .padding(.vertical, s(44))
                .padding(.horizontal, s(20))
                .frame(width: s(760))
                .frame(maxHeight: .infinity)
                .background(Color(red: 0.055, green: 0.063, blue: 0.086).opacity(0.97))
                .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1) }

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.7)
                    detailPane.padding(s(48))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var specialRow: some View {
        HStack(spacing: s(16)) {
            Image(systemName: "calendar.day.timeline.left")
                .font(tvFont(26, .semibold))
                .foregroundStyle(uiAccent)
            Text("Programmübersicht")
                .font(tvFont(28, .semibold))
                .foregroundStyle(uiText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(tvFont(20, .semibold))
                .foregroundStyle(uiSecondary.opacity(0.6))
        }
        .padding(.horizontal, s(20))
        .padding(.vertical, s(11))
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: s(14)))
        .overlay(RoundedRectangle(cornerRadius: s(14)).stroke(Color.white.opacity(0.2), lineWidth: s(1.5)))
    }

    private func sectionHeader(_ text: String, top: CGFloat) -> some View {
        Text(text)
            .font(tvFont(18, .bold))
            .foregroundStyle(uiSecondary.opacity(0.85))
            .padding(.top, top)
            .padding(.bottom, s(2))
            .padding(.horizontal, s(20))
    }

    private func row(_ entry: Entry, recentSection: Bool) -> some View {
        let selected = !recentSection && entry.num == selectedNumber
        let isCurrent = entry.num == runningNumber
        let ink: Color = selected ? .black : uiText
        let quiet: Color = selected ? Color(white: 0.3) : uiSecondary
        return HStack(spacing: s(16)) {
            Text("\(entry.num)")
                .font(tvFont(28, .bold))
                .foregroundStyle(quiet)
                .frame(width: s(52), alignment: .leading)
            ChannelEmblem(short: entry.short, width: s(68), height: s(34))
                .background(selected ? Color(red: 0.12, green: 0.15, blue: 0.20) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: s(3)) {
                HStack(spacing: s(8)) {
                    Text(entry.name)
                        .font(tvFont(26, .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    if entry.hd {
                        Text("HD")
                            .font(tvFont(15, .bold))
                            .foregroundStyle(selected ? Color.black.opacity(0.8) : uiAccent)
                            .padding(.horizontal, s(6))
                            .padding(.vertical, s(2))
                            .background(selected ? Color.black.opacity(0.12) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: s(4)))
                    }
                }
                Text("\(entry.time) · \(entry.prog)")
                    .font(tvFont(20))
                    .foregroundStyle(quiet)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if recentSection {
                OutlineBadge(text: "ZULETZT", dark: selected)
            } else if isCurrent {
                OutlineBadge(text: "LÄUFT", dark: selected)
            }
        }
        .padding(.horizontal, s(20))
        .padding(.vertical, s(9))
        .frame(height: s(74))
        .background(selected ? uiText : (isCurrent ? Color.white.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: s(14)))
        .scaleEffect(selected ? 1.03 : 1)
        .shadow(color: .black.opacity(selected ? 0.45 : 0), radius: 12, y: 6)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: s(24)) {
            HStack(spacing: s(18)) {
                ChannelEmblem(short: "ARD", width: s(120), height: s(56))
                VStack(alignment: .leading, spacing: s(4)) {
                    Text("1 · Das Erste")
                        .font(tvFont(36, .heavy))
                        .foregroundStyle(uiText)
                    HStack(spacing: s(10)) { OutlineBadge(text: "HD") }
                }
                Spacer()
            }
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)

            VStack(alignment: .leading, spacing: s(12)) {
                HStack {
                    Text("JETZT").font(tvFont(22, .bold)).foregroundStyle(uiAccent)
                    Text("· 20:15 – 21:45").font(tvFont(22, .medium)).foregroundStyle(uiSecondary)
                }
                Text("Das Gipfeltreffen – Naturdoku")
                    .font(tvFont(34, .bold))
                    .foregroundStyle(uiText)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(uiAccent).frame(width: geo.size.width * 0.31)
                    }
                }
                .frame(height: s(6))
                Text("Naturdokumentation, Deutschland 2026")
                    .font(tvFont(22, .semibold))
                    .foregroundStyle(uiText.opacity(0.9))
                Text("Hoch über den Tälern der Ostalpen leben Steinböcke, Murmeltiere und Bartgeier. Ein Jahr lang hat ein Kamerateam die Bewohner der Gipfelregion begleitet – vom ersten Schnee bis zur Almsaison.")
                    .font(tvFont(20))
                    .foregroundStyle(uiSecondary)
                    .lineLimit(4)
            }
            .padding(s(24))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: s(20)))

            VStack(alignment: .leading, spacing: s(8)) {
                Text("DANACH · Ab 21:45").font(tvFont(20, .bold)).foregroundStyle(uiSecondary)
                Text("Tagesthemen").font(tvFont(26, .bold)).foregroundStyle(uiText)
                Text("Nachrichten und Berichte aus dem In- und Ausland")
                    .font(tvFont(20))
                    .foregroundStyle(uiSecondary)
            }
            .padding(s(20))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: s(16)))

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 3. Sendungsinfo (InfoPanel) + TimeshiftBar
struct InfoPanelTimeshiftScreenshotView: View {
    /// Symbolschalter wie in der App; gewählt ist „Von Anfang an“.
    let pills = ["speaker.wave.2", "captions.bubble", "backward.end", "magnifyingglass", "gearshape"]
    let selected = 2

    var body: some View {
        ZStack {
            ScenicTVBackground(darken: 0.16)

            VStack {
                TVPanel {
                    VStack(alignment: .leading, spacing: s(28)) {
                        HStack(spacing: s(16)) {
                            ForEach(0..<pills.count, id: \.self) { index in
                                let isSelected = index == selected
                                Image(systemName: pills[index])
                                    .font(tvFont(26, .semibold))
                                    .foregroundStyle(isSelected ? Color.black : uiText)
                                    .frame(width: s(76), height: s(56))
                                    .background(isSelected ? uiText : Color.white.opacity(0.14), in: Capsule())
                                    .scaleEffect(isSelected ? 1.08 : 1)
                                    .shadow(color: .black.opacity(isSelected ? 0.45 : 0), radius: 8, y: 4)
                            }
                            Text("Von Anfang an")
                                .font(tvFont(24, .medium))
                                .foregroundStyle(uiSecondary)
                                .padding(.leading, s(8))
                            Spacer()
                        }

                        HStack(alignment: .top, spacing: s(48)) {
                            VStack(alignment: .leading, spacing: s(10)) {
                                HStack(spacing: s(12)) {
                                    ChannelEmblem(short: "ZDF", width: s(64), height: s(32))
                                    Text("ZEITVERSETZT · 2 ZDF")
                                        .font(tvFont(24, .semibold))
                                        .foregroundStyle(uiSecondary)
                                }
                                HStack(spacing: s(16)) {
                                    Text("20:15 – 21:45")
                                        .font(tvFont(26, .bold))
                                        .foregroundStyle(uiAccent)
                                    Text("Terra X: Wunder der Erde")
                                        .font(tvFont(38, .bold))
                                        .lineLimit(1)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.15))
                                        Capsule().fill(uiAccent).frame(width: geo.size.width * 0.34)
                                    }
                                }
                                .frame(height: s(6))
                                Text("Die Alpen von oben")
                                    .font(tvFont(24, .medium))
                                    .foregroundStyle(uiSecondary)
                                Text("Spektakuläre Luftaufnahmen zeigen das empfindliche Ökosystem der Alpen im Wandel der Jahreszeiten. Gletscherforscher und Biologen berichten von den höchsten Gipfeln zwischen Mont Blanc und Zugspitze.")
                                    .font(tvFont(22))
                                    .foregroundStyle(uiSecondary)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: s(8)) {
                                Text("DANACH · Ab 21:45")
                                    .font(tvFont(24, .semibold))
                                    .foregroundStyle(uiSecondary)
                                Text("heute journal")
                                    .font(tvFont(32, .bold))
                                Text("Nachrichten, Hintergründe und Wetter")
                                    .font(tvFont(22))
                                    .foregroundStyle(uiSecondary)
                                    .lineLimit(3)
                            }
                            .frame(width: s(420), alignment: .leading)
                            .padding(.leading, s(24))
                            .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: s(2)) }
                        }

                        HStack(spacing: s(20)) {
                            Label("1920×1080 (1080i HD)", systemImage: "tv")
                            Label("9.8 Mbit/s", systemImage: "speedometer")
                            Label("0 Bildfehler", systemImage: "checkmark.shield")
                            Label("Signal: 9 dB · SNR: 36 dB", systemImage: "antenna.radiowaves.left.and.right")
                            Label("Tuner 1/4", systemImage: "cpu")
                        }
                        .font(tvFont(20, .medium))
                        .foregroundStyle(uiSecondary)
                        .padding(.top, s(4))

                        Text("Links/Rechts: auswählen · Klick: Aktion ausführen · Zurück oder nach oben wischen: schließen")
                            .font(tvFont(22))
                            .foregroundStyle(uiSecondary)
                    }
                    .foregroundStyle(uiText)
                }

                Spacer()

                TVPanel {
                    VStack(alignment: .leading, spacing: s(18)) {
                        HStack {
                            Text("2 ZDF").font(tvFont(32, .bold))
                            Text("· Terra X: Wunder der Erde").font(tvFont(32)).lineLimit(1)
                            Spacer()
                            Text("Angehalten · 12:40 hinter Live")
                                .font(tvFont(32, .bold))
                                .foregroundStyle(uiAccent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .trailing) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(Color.white.opacity(0.5)).frame(width: geo.size.width * 0.14)
                            }
                        }
                        .frame(height: s(12))
                        Text("Play/Pause: weiter/anhalten · Links/Rechts: spulen (10 s, 30 s, 1 m, 3 m, 5 m) · rechts bis zum Ende: Live")
                            .font(tvFont(24))
                            .foregroundStyle(uiSecondary)
                    }
                    .foregroundStyle(uiText)
                }
            }
            .padding(.horizontal, safeHorizontal)
            .padding(.vertical, safeVertical)
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
             date: "30.10.2026 · 20:15 Uhr", duration: "44 Min.", hd: true, ut: true,
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
    save(ChannelListScreenshotView(), to: "senderliste.png")
    save(InfoPanelTimeshiftScreenshotView(), to: "sendungsinfo-timeshift.png")
    save(MediathekScreenshotView(), to: "mediathek-suche.png")
}
