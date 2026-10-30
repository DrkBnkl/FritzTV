import SwiftUI
import FritzTVKit

/// EPG-Programmübersicht mit Zeitstrahl über alle Sender.
///
/// Optik orientiert an `docs/screenshots/epg-zeitstrahl.png`:
/// Großer Kopfbereich mit Live-Bild links und Sendungsdetails rechts, darunter Zeitleiste
/// mit dunklen Kacheln, Fortschrittsbalken und roter „Jetzt“-Linie.
///
/// Bedienung (über `AppModel.handleEPG`): Hoch/Runter wählt den Sender, Links/Rechts springt im
/// Zeitstrahl von Sendung zu Sendung, Klick schaltet um bzw. öffnet Details.
struct EPGOverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @ObservedObject private var nav: EPGNavigation
    @Environment(\.windowSize) private var windowSize

    // Timeline-Konfiguration; Maße abgestimmt auf das 16:9-Layout
    private let pointsPerMinute: CGFloat = EPGMetrics.s(6.1)
    private let totalHours: Int = 30
    private let rowHeight: CGFloat = EPGMetrics.s(66)
    private let rulerHeight: CGFloat = EPGMetrics.s(38)
    private let channelColumnWidth: CGFloat = EPGMetrics.s(252)

    /// Beginn des Zeitstrahls (volle Stunde, 6 Stunden vor jetzt für „Sendung verpasst“).
    @State private var windowStart: Date = EPGOverviewView.makeWindowStart()
    /// Kacheln je Senderplatz, neu berechnet nur bei neuen Programmdaten.
    @State private var rowItems: [Int: [TimelineItem]] = [:]
    /// Senkrechter Versatz der Zeilenliste in Punkten für weiches Blättern ohne Zeilensprünge.
    @State private var scrollOffset: CGFloat = 0
    /// Höhe des Zeilenrasters (ohne Zeitleiste).
    @State private var rasterHeight: CGFloat = 0
    /// Anzahl ganz sichtbarer Zeilen, aus der Höhe des Rasters.
    @State private var visibleRows = 6
    @State private var lastRebuild = Date.distantPast
    @State private var rebuildPending = false

    init(model: AppModel, player: PlayerController) {
        self.model = model
        self.player = player
        self.nav = model.epgNav
    }

    /// Angezeigte Sender.
    private var entries: [LineupEntry] {
        model.epgEntries
    }

    /// Platznummer des ausgewählten Senders.
    private var selectedChannelNumber: Int? {
        selectedEntry?.number
    }

    private var selectedEntry: LineupEntry? {
        entries.first { AppModel.key($0) == nav.selectedKey }
    }

    private var selectedIndex: Int {
        entries.firstIndex { AppModel.key($0) == nav.selectedKey } ?? 0
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(totalHours * 60) * pointsPerMinute
    }

    private func x(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(windowStart) / 60) * pointsPerMinute
    }

    /// Zeitpunkt, um den es geht: der Cursor (Links/Rechts) oder jetzt.
    private var focusTime: Date { nav.cursorTime ?? Date() }

    /// Waagerechte Verschiebung: Die fokussierte Zeit steht eine halbe Stunde vom linken Rand.
    private var horizontalOffset: CGFloat {
        max(0, min(x(for: focusTime) - 30 * pointsPerMinute, totalTimelineWidth - 600))
    }

    /// Fokussierte Sendung des gewählten Senders.
    private var focusedProgram: EPGProgram? {
        guard let entry = selectedEntry else { return nil }
        let items = rowItems[entry.number] ?? []
        if let id = Self.programID(in: items, at: focusTime) {
            return items.first { $0.id == id }?.program
        }
        return player.epgStore.schedule(forChannelNames: entry.group.epgNames)?.programs
            .first { $0.startDate <= focusTime && focusTime < $0.endDate }
    }

    static func makeWindowStart(now: Date = Date()) -> Date {
        let earlier = now.addingTimeInterval(-6 * 3600)
        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: earlier)
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? earlier
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM · HH:mm 'Uhr'"
        return formatter
    }()

    private var headerDateString: String { Self.headerFormatter.string(from: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(EPGColors.line).frame(height: 1)
            timelineBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let detail = nav.detail {
                EPGDetailPanel(model: model,
                               detail: detail,
                               channelName: model.lineup?.entries.first { AppModel.key($0) == detail.key }?.group.displayName ?? "",
                               actions: model.epgDetailActions(for: detail))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: nav.detail)
        .background {
            EPGColors.background
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuildRows()
            if rasterHeight > 0 {
                scrollOffset = targetScrollOffset(for: selectedIndex, viewportHeight: rasterHeight)
            }
            DebugLog.log("Übersicht sichtbar: \(entries.count) Zeilen, Auswahl \(selectedIndex)")
        }
        .onChange(of: player.epgRevision) { _, _ in scheduleRebuild() }
        .onChange(of: model.lineup?.entries.count) { _, _ in rebuildRows() }
        .onChange(of: model.showEPGOverview) { _, isShowing in
            if isShowing {
                if Date().timeIntervalSince(lastRebuild) > 900 {
                    rebuildRows()
                }
                let vh = rasterHeight > 0 ? rasterHeight : (rowHeight * CGFloat(visibleRows))
                scrollOffset = targetScrollOffset(for: selectedIndex, viewportHeight: vh)
            }
        }
        .onChange(of: nav.selectedKey) { _, _ in
            DebugLog.log("Übersicht: Auswahl geändert")
            let vh = rasterHeight > 0 ? rasterHeight : (rowHeight * CGFloat(visibleRows))
            scrollOffset = targetScrollOffset(for: selectedIndex, viewportHeight: vh)
        }
        #if os(macOS)
        .onMacScrollWheel { dx, dy in
            guard nav.detail == nil else { return }
            if abs(dy) >= abs(dx) {
                let maxOffset = max(0, CGFloat(entries.count) * rowHeight - rasterHeight)
                scrollOffset = max(0, min(maxOffset, scrollOffset - dy))
            } else {
                let deltaMinutes = Double(-dx / pointsPerMinute)
                model.scrollEPGTime(bySeconds: deltaMinutes * 60)
            }
        }
        #endif
    }

    /// Zentriert die Auswahl im sichtbaren Raster, am Anfang und Ende des Rasters weich begrenzt.
    private func targetScrollOffset(for index: Int, viewportHeight: CGFloat) -> CGFloat {
        guard !entries.isEmpty, viewportHeight > 0 else { return 0 }
        let totalHeight = CGFloat(entries.count) * rowHeight
        guard totalHeight > viewportHeight else { return 0 }
        let selectedY = CGFloat(index) * rowHeight
        let ideal = selectedY - (viewportHeight - rowHeight) / 2
        let maxOffset = totalHeight - viewportHeight
        return max(0, min(ideal, maxOffset))
    }

    /// Neue Programmdaten kommen in schneller Folge: höchstens alle 3 Sekunden neu berechnen.
    private func scheduleRebuild() {
        let wait = 3 - Date().timeIntervalSince(lastRebuild)
        if wait <= 0 {
            rebuildRows()
        } else if !rebuildPending {
            rebuildPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                rebuildPending = false
                rebuildRows()
            }
        }
    }

    private func rebuildRows() {
        let began = Date()
        defer { DebugLog.log("Übersicht: Zeilen berechnet in \(Int(Date().timeIntervalSince(began) * 1000)) ms") }
        let start = Self.makeWindowStart()
        let end = start.addingTimeInterval(Double(totalHours) * 3600)
        var items: [Int: [TimelineItem]] = [:]
        for entry in model.lineup?.entries ?? [] {
            items[entry.number] = buildTimelineItems(for: entry, start: start, end: end)
        }
        windowStart = start
        rowItems = items
        lastRebuild = Date()
    }

    // MARK: - Kopfbereich (Preview links, Sendungsdetails rechts)

    private var livePreviewSize: CGSize {
        #if os(macOS)
        if windowSize.height < 520 || windowSize.width < 900 {
            return CGSize(width: 220, height: 124)
        } else if windowSize.height < 680 || windowSize.width < 1200 {
            return CGSize(width: 280, height: 158)
        }
        #endif
        return EPGMetrics.previewSize
    }

    private var headerHeight: CGFloat {
        livePreviewSize.height + EPGMetrics.s(36)
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: EPGMetrics.s(26)) {
            livePreview
            headerProgramDetails
        }
        .padding(.horizontal, EPGMetrics.s(26))
        .padding(.vertical, EPGMetrics.s(18))
        .frame(height: headerHeight)
        .background(EPGColors.header)
    }

    /// Platzhalter für das Live-Bild links: Die Bildfläche selbst liegt in `RootView` und wird
    /// über `EPGPreviewFrameKey` verkleinert genau hierher gelegt.
    private var livePreview: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black)
            .frame(width: livePreviewSize.width, height: livePreviewSize.height)
            .background(GeometryReader { geo in
                Color.clear.preference(key: EPGPreviewFrameKey.self, value: geo.frame(in: .global))
            })
            #if os(macOS)
            .contentShape(Rectangle())
            .onTapGesture { model.closeEPGOverview() }
            .help("Klicken für Vollbild")
            #endif
    }

    /// Sendungsdetails rechts neben dem Live-Bild
    private var headerProgramDetails: some View {
        let entry = selectedEntry
        let prog = focusedProgram
        let now = Date()

        return VStack(alignment: .leading, spacing: EPGMetrics.s(8)) {
            // Zeile 1: Überschrift links & Datum/Uhrzeit / Steuerung rechts
            HStack(alignment: .center) {
                Text("Programmübersicht")
                    .font(EPGMetrics.font(15, .bold))
                    .foregroundStyle(EPGColors.accent)

                Spacer()

                Text(headerDateString)
                    .font(EPGMetrics.font(15, .medium))
                    .foregroundStyle(EPGColors.secondaryText)

                #if os(macOS)
                if nav.cursorTime != nil {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) { model.epgCursorTime = nil }
                    }) {
                        BadgePill(text: "Jetzt", fg: Color(red: 0.04, green: 0.08, blue: 0.14), bg: EPGColors.accent, size: 12)
                    }
                    .buttonStyle(.plain)
                    .help("Zur aktuellen Uhrzeit springen")
                }
                Button(action: { model.closeEPGOverview() }) {
                    BadgePill(text: "✕", fg: EPGColors.secondaryText, bg: Color.white.opacity(0.12), size: 12)
                }
                .buttonStyle(.plain)
                .help("Programmübersicht schließen (Esc)")
                #endif
            }

            // Zeile 2: Sender & Badges
            HStack(spacing: EPGMetrics.s(10)) {
                if let entry = entry {
                    Text("\(entry.number) · \(entry.group.displayName)")
                        .font(EPGMetrics.font(18, .bold))
                        .foregroundStyle(EPGColors.secondaryText)
                }

                if let prog = prog {
                    let isLive = prog.isLive(at: now)
                    let isPast = prog.endDate <= now

                    if isLive {
                        BadgePill(text: "JETZT",
                                  fg: Color(red: 0.04, green: 0.08, blue: 0.14),
                                  bg: EPGColors.accent,
                                  size: 12)
                    } else if isPast {
                        BadgePill(text: "VERGANGEN",
                                  fg: EPGColors.secondaryText,
                                  bg: Color.white.opacity(0.09),
                                  size: 12)
                    } else {
                        BadgePill(text: "DEMNÄCHST",
                                  fg: EPGColors.secondaryText,
                                  bg: Color.white.opacity(0.09),
                                  size: 12)
                    }

                    let startStr = EPGOverviewView.formatTime(prog.startDate)
                    let endStr = EPGOverviewView.formatTime(prog.endDate)
                    let timePillText: String = {
                        if isLive {
                            let rem = max(1, Int(prog.endDate.timeIntervalSince(now) / 60))
                            return "\(startStr) – \(endStr) · noch \(rem) Min."
                        } else {
                            let dur = max(1, Int(prog.duration / 60))
                            return "\(startStr) – \(endStr) · \(dur) Min."
                        }
                    }()
                    BadgePill(text: timePillText,
                              fg: EPGColors.secondaryText,
                              bg: Color.white.opacity(0.09),
                              size: 12)
                }
            }

            // Zeile 3: Sendungstitel
            Text(prog?.title ?? entry?.group.displayName ?? "Programmübersicht")
                .font(EPGMetrics.font(27, .heavy))
                .foregroundStyle(EPGColors.text)
                .lineLimit(1)

            // Zeile 4: Untertitel / Kategorie / Dauer
            if let sub = prog?.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(EPGMetrics.font(16, .semibold))
                    .foregroundStyle(EPGColors.accent)
                    .lineLimit(1)
            } else if let prog = prog {
                Text("\(Int(prog.duration / 60)) Minuten")
                    .font(EPGMetrics.font(16, .semibold))
                    .foregroundStyle(EPGColors.accent)
                    .lineLimit(1)
            }

            // Zeile 5: Beschreibung
            if let desc = prog?.description, !desc.isEmpty, desc != prog?.subtitle {
                Text(desc)
                    .font(EPGMetrics.font(15, .regular))
                    .foregroundStyle(EPGColors.secondaryText)
                    .lineLimit(2)
            } else if prog == nil {
                Text("Für diesen Sender liegen derzeit keine Programminformationen vor.")
                    .font(EPGMetrics.font(15, .regular))
                    .foregroundStyle(EPGColors.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Zeile 6: Tasten-Hinweise
            HStack(spacing: EPGMetrics.s(18)) {
                hintItem("Hoch/Runter", "Sender")
                hintItem("Links/Rechts", "Zeit (-6 Std. bis +24 Std.)")
                hintItem("Klick", "Umschalten / Details")
                hintItem("Play/Pause", "Von Anfang an & Mediathek")
                hintItem("Zurück", "Live-TV")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hintItem(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            BadgePill(text: key, fg: EPGColors.text, bg: Color.white.opacity(0.12), size: 12)
            Text(label)
                .font(EPGMetrics.font(13, .medium))
                .foregroundStyle(EPGColors.secondaryText)
        }
    }

    // MARK: - Raster

    private var timelineBody: some View {
        let now = Date()
        let focus = focusTime
        let offset = horizontalOffset
        let all = entries
        let selected = selectedChannelNumber

        return GeometryReader { geo in
            let timelineWidth = max(0, geo.size.width - channelColumnWidth)
            let rowsHeight = max(0, geo.size.height - rulerHeight)

            VStack(spacing: 0) {
                rulerRow(now: now, offset: offset, timelineWidth: timelineWidth)
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(all) { entry in
                            let isSelected = entry.number == selected
                            let items = rowItems[entry.number] ?? []
                            row(entry: entry, items: items, isSelected: isSelected,
                                focus: focus, now: now, offset: offset, timelineWidth: timelineWidth)
                        }
                    }
                    .offset(y: -scrollOffset)

                    nowLine(now: now, offset: offset)
                }
                .frame(width: geo.size.width, height: rowsHeight, alignment: .topLeading)
                .clipped()
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear {
                rasterHeight = rowsHeight
                updateVisibleRows(height: rowsHeight)
                scrollOffset = targetScrollOffset(for: selectedIndex, viewportHeight: rowsHeight)
            }
            .onChange(of: rowsHeight) { _, height in
                rasterHeight = height
                updateVisibleRows(height: height)
                scrollOffset = targetScrollOffset(for: selectedIndex, viewportHeight: height)
            }
        }
    }

    private func updateVisibleRows(height: CGFloat) {
        let rows = max(3, Int(height / rowHeight))
        DebugLog.log("Übersicht: Rasterhöhe \(Int(height)), Zeilenhöhe \(Int(rowHeight)), \(rows) Zeilen")
        nav.pageSize = rows
        visibleRows = rows
    }

    private func row(entry: LineupEntry, items: [TimelineItem], isSelected: Bool,
                     focus: Date, now: Date, offset: CGFloat, timelineWidth: CGFloat) -> some View {
        let key = AppModel.key(entry)
        return HStack(spacing: 0) {
            ChannelCell(number: entry.number,
                        name: entry.group.displayName,
                        isHD: entry.group.hd != nil,
                        isCurrent: entry.number == model.currentNumber,
                        isSelected: isSelected,
                        width: channelColumnWidth,
                        height: rowHeight - 4)
                .equatable()
                #if os(macOS)
                .contentShape(Rectangle())
                .onTapGesture { model.tuneFromEPG(key: key) }
                .help("Auf \(entry.group.displayName) umschalten")
                #endif

            TimelineRow(items: visibleItems(items, offset: offset, width: timelineWidth),
                        focusedID: isSelected ? Self.programID(in: items, at: focus) : nil,
                        liveID: Self.programID(in: items, at: now),
                        isSelected: isSelected,
                        progress: Self.liveProgress(in: items, at: now),
                        width: timelineWidth,
                        height: rowHeight,
                        onSelectProgram: { prog in
                            nav.selectedKey = key
                            nav.detail = EPGDetail(key: key, program: prog, action: 0)
                        },
                        onDoubleClickProgram: {
                            model.tuneFromEPG(key: key)
                        })
                .equatable()
                .frame(width: timelineWidth, height: rowHeight, alignment: .leading)
                .clipped()
        }
        .frame(width: channelColumnWidth + timelineWidth, height: rowHeight, alignment: .leading)
    }

    /// Kacheln im sichtbaren Ausschnitt, Lage relativ zu dessen linkem Rand.
    private func visibleItems(_ items: [TimelineItem], offset: CGFloat, width: CGFloat) -> [TimelineItem] {
        items.compactMap { item in
            let start = max(item.x, offset)
            let end = min(item.x + item.width, offset + width)
            guard end > start + 1 else { return nil }
            return TimelineItem(id: item.id, program: item.program, x: start - offset, width: end - start)
        }
    }

    /// Zeitleiste oben; bleibt beim senkrechten Blättern stehen.
    private func rulerRow(now: Date, offset: CGFloat, timelineWidth: CGFloat) -> some View {
        let nowX = channelColumnWidth + x(for: now) - offset
        return HStack(spacing: 0) {
            Text("Sender")
                .font(EPGMetrics.font(14, .bold))
                .foregroundStyle(EPGColors.secondaryText)
                .padding(.leading, EPGMetrics.s(22))
                .frame(width: channelColumnWidth, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(EPGColors.line).frame(width: 1)
                }

            ZStack(alignment: .topLeading) {
                TimeRuler(start: windowStart.addingTimeInterval(Double(offset / pointsPerMinute) * 60),
                          width: timelineWidth, pointsPerMinute: pointsPerMinute, height: rulerHeight)
                    .equatable()
                    .frame(width: timelineWidth, height: rulerHeight, alignment: .leading)
                    .clipped()

                if nowX >= channelColumnWidth {
                    Circle()
                        .fill(EPGColors.nowLine)
                        .frame(width: 10, height: 10)
                        .offset(x: nowX - channelColumnWidth - 5, y: rulerHeight - 12)
                }
            }
            .frame(width: timelineWidth, height: rulerHeight)
        }
        .frame(height: rulerHeight)
        .background(EPGColors.ruler)
        .overlay(alignment: .bottom) { Rectangle().fill(EPGColors.line).frame(height: 1) }
    }

    /// Senkrechte Linie für „jetzt“ über alle Zeilen.
    @ViewBuilder
    private func nowLine(now: Date, offset: CGFloat) -> some View {
        let xPos = channelColumnWidth + x(for: now) - offset
        if xPos >= channelColumnWidth {
            Rectangle()
                .fill(EPGColors.nowLine)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: xPos - 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Kacheln berechnen

    struct TimelineItem: Identifiable, Equatable {
        let id: String
        let program: EPGProgram?
        let x: CGFloat
        let width: CGFloat

        static func == (lhs: TimelineItem, rhs: TimelineItem) -> Bool {
            lhs.id == rhs.id && lhs.x == rhs.x && lhs.width == rhs.width
                && lhs.program?.title == rhs.program?.title
        }
    }

    private func buildTimelineItems(for entry: LineupEntry, start: Date, end: Date) -> [TimelineItem] {
        let schedule = player.epgStore.schedule(forChannelNames: entry.group.epgNames)
        let programs = (schedule?.programs ?? []).sorted { $0.startDate < $1.startDate }
        var items: [TimelineItem] = []
        var cursor = start
        for prog in programs {
            guard prog.endDate > start else { continue }
            guard prog.startDate < end else { break }
            let from = max(prog.startDate, cursor)
            let to = min(prog.endDate, end)
            guard to > from else { continue }
            let xPos = CGFloat(from.timeIntervalSince(start) / 60) * pointsPerMinute + 2
            let width = max(EPGMetrics.s(20), CGFloat(to.timeIntervalSince(from) / 60) * pointsPerMinute - 4)
            items.append(TimelineItem(id: prog.id, program: prog, x: xPos, width: width))
            cursor = to
        }
        return items
    }

    /// Kachel, die den Zeitpunkt enthält.
    static func programID(in items: [TimelineItem], at date: Date) -> String? {
        items.first { item in
            guard let p = item.program else { return false }
            return p.startDate <= date && date < p.endDate
        }?.id
    }

    /// Fortschritt der laufenden Sendung, auf 2 % gerundet (seltener neu zeichnen).
    static func liveProgress(in items: [TimelineItem], at date: Date) -> Double {
        guard let id = programID(in: items, at: date),
              let p = items.first(where: { $0.id == id })?.program else { return 0 }
        return (p.progress(at: date) * 50).rounded() / 50
    }

    static func formatTime(_ date: Date) -> String {
        UI.timeFormatter.string(from: date)
    }
}

// MARK: - Farben

/// Farben der Programmübersicht, abgestimmt auf `docs/screenshots/epg-zeitstrahl.png`.
enum EPGColors {
    static let background = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let header = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let ruler = Color(red: 0.05, green: 0.08, blue: 0.13)
    static let column = Color(red: 0.05, green: 0.08, blue: 0.13)
    static let columnSelected = Color(red: 0.11, green: 0.19, blue: 0.31)
    static let line = Color.white.opacity(0.12)
    static let tile = Color(red: 0.08, green: 0.12, blue: 0.19).opacity(0.92)
    static let tilePast = Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.75)
    static let tileSelected = Color(red: 0.16, green: 0.28, blue: 0.46)
    static let accent = Color(red: 0.50, green: 0.78, blue: 1.0)
    static let nowLine = Color(red: 1.0, green: 0.38, blue: 0.35)
    static let liveGreen = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let text = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let secondaryText = Color(red: 0.66, green: 0.69, blue: 0.74)
    static let tertiaryText = Color(white: 0.52)
    static let cell = tile
    static let cellBorder = Color.white.opacity(0.10)
    static let liveCell = tile
    static let focusCell = tileSelected
    static let selectedRow = columnSelected
}

// MARK: - Hilfs-Views

struct BadgePill: View {
    let text: String
    var fg: Color = EPGColors.accent
    var bg: Color = EPGColors.accent.opacity(0.16)
    var size: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Zeilenbausteine

private struct ChannelCell: View, Equatable {
    let number: Int
    let name: String
    let isHD: Bool
    let isCurrent: Bool
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    static func == (lhs: ChannelCell, rhs: ChannelCell) -> Bool {
        lhs.number == rhs.number
            && lhs.name == rhs.name
            && lhs.isHD == rhs.isHD
            && lhs.isCurrent == rhs.isCurrent
            && lhs.isSelected == rhs.isSelected
            && lhs.width == rhs.width
            && lhs.height == rhs.height
    }

    var body: some View {
        HStack(spacing: EPGMetrics.s(10)) {
            Text("\(number)")
                .font(EPGMetrics.font(15, .bold, design: .monospaced))
                .foregroundStyle(isSelected ? EPGColors.accent : (isCurrent ? EPGColors.accent : EPGColors.secondaryText))
                .frame(width: EPGMetrics.s(24), alignment: .trailing)

            ChannelLogoView(channelName: name, height: EPGMetrics.s(28), maxWidth: EPGMetrics.s(46))

            Text(name)
                .font(EPGMetrics.font(15, isSelected ? .bold : .medium))
                .foregroundStyle(isCurrent ? EPGColors.accent : EPGColors.text)
                .lineLimit(1)

            if isHD {
                BadgePill(text: "HD",
                          fg: isSelected ? Color.white : EPGColors.accent,
                          bg: Color.white.opacity(0.12),
                          size: EPGMetrics.s(11))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, EPGMetrics.s(10))
        .frame(width: width, height: height, alignment: .leading)
        .background(isSelected ? EPGColors.columnSelected : EPGColors.column)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(EPGColors.accent).frame(width: 4)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(EPGColors.line).frame(width: 1)
        }
    }
}

private struct TimelineRow: View, Equatable {
    let items: [EPGOverviewView.TimelineItem]
    let focusedID: String?
    let liveID: String?
    let isSelected: Bool
    let progress: Double
    let width: CGFloat
    let height: CGFloat
    var onSelectProgram: ((EPGProgram) -> Void)? = nil
    var onDoubleClickProgram: (() -> Void)? = nil

    static func == (lhs: TimelineRow, rhs: TimelineRow) -> Bool {
        lhs.items == rhs.items
            && lhs.focusedID == rhs.focusedID
            && lhs.liveID == rhs.liveID
            && lhs.isSelected == rhs.isSelected
            && lhs.progress == rhs.progress
            && lhs.width == rhs.width
            && lhs.height == rhs.height
    }

    var body: some View {
        let now = Date()
        ZStack(alignment: .topLeading) {
            if items.isEmpty {
                Text("Keine Programmdaten")
                    .font(EPGMetrics.font(14, .regular))
                    .foregroundStyle(EPGColors.secondaryText.opacity(0.6))
                    .padding(.horizontal, 14)
                    .frame(height: height)
            }
            ForEach(items) { item in
                if let prog = item.program {
                    let isFocused = item.id == focusedID
                    let isLive = item.id == liveID
                    let isPast = prog.endDate <= now
                    ProgramBlockView(prog: prog,
                                     isLive: isLive,
                                     isFocused: isFocused,
                                     isPast: isPast,
                                     progress: isLive ? progress : 0,
                                     width: item.width,
                                     height: height - 4)
                        #if os(macOS)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            onDoubleClickProgram?()
                        }
                        .onTapGesture {
                            onSelectProgram?(prog)
                        }
                        #endif
                        .offset(x: item.x, y: 2)
                        .zIndex(isFocused ? 1 : 0)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

private struct TimeRuler: View, Equatable {
    /// Zeit am linken Rand des sichtbaren Ausschnitts.
    let start: Date
    let width: CGFloat
    let pointsPerMinute: CGFloat
    let height: CGFloat

    static func == (lhs: TimeRuler, rhs: TimeRuler) -> Bool {
        lhs.start == rhs.start
            && lhs.width == rhs.width
            && lhs.pointsPerMinute == rhs.pointsPerMinute
            && lhs.height == rhs.height
    }

    var body: some View {
        let step: TimeInterval = 30 * 60
        let first = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 / step) * step)
        let count = Int(ceil(Double(width / pointsPerMinute) / 30)) + 3
        ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { index in
                let date = first.addingTimeInterval(Double(index) * step)
                let isFullHour = Calendar.current.component(.minute, from: date) == 0
                let isMidnight = isFullHour && Calendar.current.component(.hour, from: date) == 0
                let label: String = {
                    if isMidnight {
                        return "\(Self.dayName(date)) \(EPGOverviewView.formatTime(date))"
                    }
                    return EPGOverviewView.formatTime(date)
                }()
                let xPos = CGFloat(date.timeIntervalSince(start) / 60) * pointsPerMinute + 6

                Text(label)
                    .font(EPGMetrics.font(14, .semibold, design: .monospaced))
                    .foregroundStyle(EPGColors.secondaryText)
                    .frame(height: height, alignment: .center)
                    .offset(x: xPos)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE"
        return f
    }()

    static func dayName(_ date: Date) -> String { dayFormatter.string(from: date) }
}

private struct ProgramBlockView: View {
    let prog: EPGProgram
    let isLive: Bool
    let isFocused: Bool
    let isPast: Bool
    let progress: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let tStr = "\(EPGOverviewView.formatTime(prog.startDate)) – \(EPGOverviewView.formatTime(prog.endDate))"
        VStack(alignment: .leading, spacing: 4) {
            Text(prog.title)
                .font(EPGMetrics.font(15, isLive ? .bold : .medium))
                .foregroundStyle(isPast ? EPGColors.secondaryText.opacity(0.75) : EPGColors.text)
                .lineLimit(1)

            Text(tStr)
                .font(EPGMetrics.font(12, .medium, design: .monospaced))
                .foregroundStyle(isPast ? EPGColors.secondaryText.opacity(0.55) : EPGColors.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isLive {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16)).frame(height: 3)
                        Capsule().fill(EPGColors.accent)
                            .frame(width: max(geo.size.width * progress, 5), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, EPGMetrics.s(10))
        .padding(.vertical, EPGMetrics.s(8))
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            isFocused ? EPGColors.tileSelected : (isPast ? EPGColors.tilePast : EPGColors.tile),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused ? EPGColors.accent : (isLive ? EPGColors.accent.opacity(0.45) : Color.white.opacity(0.10)),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        #if os(macOS)
        .help(tooltipText)
        #endif
    }

    private var tooltipText: String {
        var lines = [prog.title,
                     "\(EPGOverviewView.formatTime(prog.startDate)) – \(EPGOverviewView.formatTime(prog.endDate)) (\(Int(prog.duration / 60)) Min.)"]
        if let sub = prog.subtitle, !sub.isEmpty { lines.append(sub) }
        if let desc = prog.description, !desc.isEmpty, desc != prog.subtitle { lines.append(desc) }
        return lines.joined(separator: "\n\n")
    }
}

/// Maße der Programmübersicht.
enum EPGMetrics {
    #if os(tvOS)
    static let k: CGFloat = 1.3
    static let previewSize = CGSize(width: 440, height: 248)
    #else
    static let k: CGFloat = 1.0
    static let previewSize = CGSize(width: 376, height: 212)
    #endif

    static func s(_ value: CGFloat) -> CGFloat { value * k }

    /// Apple TV: mindestens 23 pt (Apple-Richtlinien).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        #if os(tvOS)
        .system(size: max(size * k, UI.minimumFontSize), weight: weight, design: design)
        #else
        .system(size: size * k, weight: weight, design: design)
        #endif
    }
}

/// Auswahl in der Programmübersicht (siehe `AppModel.epgNav`).
@MainActor
final class EPGNavigation: ObservableObject {
    @Published var selectedKey: String?
    @Published var cursorTime: Date?
    /// Geöffnete Detailtafel zu einer Sendung.
    @Published var detail: EPGDetail?
    /// Ganz sichtbare Zeilen (für seitenweises Blättern), setzt die Übersicht.
    var pageSize = 5
}

struct EPGDetail: Equatable {
    let key: String
    let program: EPGProgram
    /// Gewählte Aktion (siehe `AppModel.epgDetailActions`).
    var action: Int
}

/// Detailtafel zu einer Sendung in der Programmübersicht (mit Mediathek-Suche und Umschalten).
private struct EPGDetailPanel: View {
    @ObservedObject var model: AppModel
    let detail: EPGDetail
    let channelName: String
    let actions: [AppModel.EPGDetailAction]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()

    var body: some View {
        let p = detail.program
        let now = Date()
        let isPast = p.endDate <= now
        let isLive = p.startDate <= now && now < p.endDate
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                #if os(macOS)
                .onTapGesture { model.epgNav.detail = nil }
                #endif

            VStack(alignment: .leading, spacing: UI.s(20)) {
                HStack(spacing: UI.s(16)) {
                    Text("\(channelName) · \(Self.dayFormatter.string(from: p.startDate)) · \(EPGOverviewView.formatTime(p.startDate)) – \(EPGOverviewView.formatTime(p.endDate)) Uhr")
                        .font(UI.font(26, .semibold))
                        .foregroundStyle(EPGColors.accent)
                    if isLive {
                        Text("LÄUFT")
                            .font(UI.font(20, .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, UI.s(12))
                            .padding(.vertical, UI.s(4))
                            .background(EPGColors.accent, in: Capsule())
                    } else if isPast {
                        Text("VERGANGEN")
                            .font(UI.font(20, .bold))
                            .foregroundStyle(EPGColors.secondaryText)
                            .padding(.horizontal, UI.s(12))
                            .padding(.vertical, UI.s(4))
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
                Text(p.title)
                    .font(UI.font(48, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let sub = p.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(UI.font(30, .medium))
                        .foregroundStyle(EPGColors.secondaryText)
                        .lineLimit(2)
                }
                if let desc = p.description, !desc.isEmpty, desc != p.subtitle {
                    Text(desc)
                        .font(UI.font(29))
                        .foregroundStyle(EPGColors.secondaryText)
                        .lineLimit(6)
                }
                HStack(spacing: UI.s(20)) {
                    ForEach(actions.indices, id: \.self) { index in
                        let selected = index == detail.action
                        Text(actions[index].title)
                            .font(UI.font(29, .semibold))
                            .foregroundStyle(selected ? Color.black : .white)
                            .padding(.horizontal, UI.s(32))
                            .padding(.vertical, UI.s(16))
                            .background(selected ? Color.white : Color.white.opacity(0.14), in: Capsule())
                            .focusLift(selected, scale: 1.08)
                            #if os(macOS)
                            .contentShape(Capsule())
                            .onHover { hovering in
                                if hovering {
                                    model.epgNav.detail?.action = index
                                }
                            }
                            .onTapGesture {
                                model.executeEPGDetailAction(actions[index], for: detail)
                            }
                            #endif
                    }
                }
                .padding(.top, UI.s(12))
            }
            .padding(UI.s(56))
            .frame(maxWidth: UI.s(1300), alignment: .leading)
            .background { PanelBackground(cornerRadius: UI.s(32)) }
        }
    }
}
