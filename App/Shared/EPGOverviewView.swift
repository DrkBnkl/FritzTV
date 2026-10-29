import SwiftUI
import FritzTVKit

/// EPG-Programmübersicht mit Zeitstrahl über alle Sender.
///
/// Bedienung (über `AppModel.handleEPG`): Hoch/Runter wählt den Sender, Links/Rechts springt im
/// Zeitstrahl von Sendung zu Sendung, Klick schaltet um.
///
/// Leistung auf dem Apple TV: Es gibt keine ScrollView. Gezeichnet werden nur die sichtbaren
/// Zeilen (plus Rand); sie liegen an festen Positionen und werden beim Blättern nur per Versatz
/// verschoben – das ist eine reine Transformation und läuft flüssig. Die Kacheln werden nur bei
/// neuen Programmdaten berechnet (`rowItems`), die Zeilen sind `Equatable`. Die Auswahl liegt in
/// einem eigenen Objekt (`EPGNavigation`), damit nicht die ganze App neu gezeichnet wird.
struct EPGOverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @ObservedObject private var nav: EPGNavigation

    // Timeline-Konfiguration; alle Maße über EPGMetrics (auf dem Apple TV deutlich größer)
    private let pointsPerMinute: CGFloat = EPGMetrics.s(4.0)
    private let totalHours: Int = 30
    private let rowHeight: CGFloat = EPGMetrics.s(68)
    private let rulerHeight: CGFloat = EPGMetrics.s(40)
    private let channelColumnWidth: CGFloat = EPGMetrics.s(250)

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

    /// Platznummer des ausgewählten Senders (Auswahl liegt im Modell, siehe `AppModel.handleEPG`).
    private var selectedChannelNumber: Int? {
        entries.first { AppModel.key($0) == nav.selectedKey }?.number
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
            ZStack {
                Color.black.opacity(0.88)
                Rectangle().fill(.ultraThickMaterial).opacity(0.4)
            }
            .ignoresSafeArea()
        }
        // Keine eigene Fokus- oder Tastensteuerung: Fernbedienung und Tastatur laufen wie bei der
        // Senderliste über `AppModel.handle`. Zwei konkurrierende Steuerungen führten dazu, dass
        // Hoch/Runter im Hintergrund den Live-Sender wechselte statt die Auswahl zu bewegen.
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
        .onChange(of: nav.selectedKey) { _, _ in
            DebugLog.log("Übersicht: Auswahl geändert")
            let target = targetScrollOffset(for: selectedIndex, viewportHeight: rasterHeight)
            withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.90)) {
                scrollOffset = target
            }
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

    // MARK: - Kopfzeile

    /// Schmale Kopfzeile: links Datum, Uhrzeit und Bedienhinweis, rechts das kleine Live-Bild.
    /// Darunter beginnt direkt das Raster.
    private var headerBar: some View {
        HStack(alignment: .center, spacing: EPGMetrics.s(24)) {
            VStack(alignment: .leading, spacing: EPGMetrics.s(10)) {
                HStack(spacing: EPGMetrics.s(16)) {
                    Text(headerDateString)
                        .font(EPGMetrics.font(20, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    #if os(macOS)
                    if nav.cursorTime != nil {
                        headerButton("Jetzt") {
                            withAnimation(.easeInOut(duration: 0.25)) { model.epgCursorTime = nil }
                        }
                    }
                    headerButton("Schließen") { model.closeEPGOverview() }
                        .help("Programmübersicht schließen (Esc)")
                    #endif
                }

                Text("\(UI.upDown): Sender · \(UI.leftRight): Zeitstrahl · \(UI.select): umschalten / Details · \(UI.playPause): Details / Jetzt · \(UI.back): schließen")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .font(EPGMetrics.font(14, .medium))
                    .foregroundStyle(EPGColors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            livePreview
        }
        .padding(.horizontal, EPGMetrics.s(22))
        .padding(.vertical, EPGMetrics.s(10))
        .background(EPGColors.header)
    }

    #if os(macOS)
    private func headerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EPGMetrics.font(15, .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(EPGColors.cell, in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    #endif

    /// Platzhalter für das Live-Bild: Die Bildfläche selbst liegt in `RootView` und wird
    /// über `EPGPreviewFrameKey` verkleinert genau hierher gelegt.
    private var livePreview: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.black)
            .frame(width: EPGMetrics.previewSize.width, height: EPGMetrics.previewSize.height)
            .background(GeometryReader { geo in
                Color.clear.preference(key: EPGPreviewFrameKey.self, value: geo.frame(in: .global))
            })
            #if os(macOS)
            .contentShape(Rectangle())
            .onTapGesture { model.closeEPGOverview() }
            .help("Klicken für Vollbild")
            #endif
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
            let effectiveHeight = rowsHeight > 0 ? rowsHeight : 800
            let firstVisible = max(0, Int(floor(scrollOffset / rowHeight)) - 3)
            let lastVisible = min(all.count - 1, Int(ceil((scrollOffset + effectiveHeight) / rowHeight)) + 3)

            VStack(spacing: 0) {
                rulerRow(now: now, offset: offset, timelineWidth: timelineWidth)
                ZStack(alignment: .topLeading) {
                    if firstVisible <= lastVisible {
                        ForEach(firstVisible...lastVisible, id: \.self) { index in
                            let entry = all[index]
                            let isSelected = entry.number == selected
                            let items = rowItems[entry.number] ?? []
                            row(entry: entry, items: items, isSelected: isSelected,
                                focus: focus, now: now, offset: offset, timelineWidth: timelineWidth)
                                .offset(y: CGFloat(index) * rowHeight - scrollOffset)
                        }
                    }

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
        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.90), value: nav.cursorTime)
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
                        height: rowHeight)
                .equatable()
                #if os(macOS)
                .contentShape(Rectangle())
                .onTapGesture { model.tuneFromEPG(key: key) }
                .help("Auf \(entry.group.displayName) umschalten")
                #endif

            // Nur der sichtbare Ausschnitt wird gezeichnet: Ein 30-Stunden-Streifen je Zeile
            // kostete sonst auf dem Apple TV bei jeder Änderung Sekunden.
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
        .background(isSelected ? Color.white.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EPGColors.line.opacity(0.5)).frame(height: 1)
        }
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
        HStack(spacing: 0) {
            HStack(spacing: EPGMetrics.s(8)) {
                Image(systemName: "clock")
                    .font(EPGMetrics.font(14, .semibold))
                    .foregroundStyle(EPGColors.accent)
                if let cursor = nav.cursorTime {
                    Text("\(cursor < now ? "um" : "ab") \(Self.formatTime(cursor))")
                        .font(EPGMetrics.font(15, .bold))
                        .foregroundStyle(EPGColors.accent)
                } else {
                    Text("Jetzt")
                        .font(EPGMetrics.font(15, .bold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .padding(.horizontal, EPGMetrics.s(14))
            .frame(width: channelColumnWidth, height: rulerHeight, alignment: .leading)
            .background(EPGColors.ruler)
            .overlay(alignment: .trailing) {
                Rectangle().fill(EPGColors.line).frame(width: 1)
            }

            TimeRuler(start: windowStart.addingTimeInterval(Double(offset / pointsPerMinute) * 60),
                      width: timelineWidth, pointsPerMinute: pointsPerMinute, height: rulerHeight)
                .equatable()
                .frame(width: timelineWidth, height: rulerHeight, alignment: .leading)
                .clipped()
                .background(EPGColors.ruler)
        }
        .frame(height: rulerHeight)
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
            let xPos = CGFloat(from.timeIntervalSince(start) / 60) * pointsPerMinute
            let width = max(EPGMetrics.s(36), CGFloat(to.timeIntervalSince(from) / 60) * pointsPerMinute - 3)
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

/// Farben der Programmübersicht (dunkel mit Transparenzeffekten, passend zur Info- und Senderauswahl).
enum EPGColors {
    static let background = Color(red: 0.055, green: 0.063, blue: 0.086).opacity(0.94)
    static let header = Color.black.opacity(0.60)
    static let column = Color.black.opacity(0.40)
    static let ruler = Color.black.opacity(0.48)
    static let line = Color.white.opacity(0.10)
    static let cell = Color.white.opacity(0.08)
    static let cellBorder = Color.white.opacity(0.14)
    static let liveCell = Color.white.opacity(0.16)
    static let focusCell = Color.white
    static let selectedRow = Color.white.opacity(0.05)
    static let accent = UI.accent
    static let nowLine = UI.accent
    static let secondaryText = Color(white: 0.75)
    static let tertiaryText = Color(white: 0.52)
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
                .font(EPGMetrics.font(18, .bold))
                .foregroundStyle(isCurrent ? EPGColors.accent : (isSelected ? Color.white : EPGColors.secondaryText))
                .frame(width: EPGMetrics.s(36), alignment: .leading)

            ChannelLogoView(channelName: name, height: EPGMetrics.s(28), maxWidth: EPGMetrics.s(52))

            Text(name)
                .font(EPGMetrics.font(17, isSelected ? .bold : .semibold))
                .foregroundStyle(isCurrent ? EPGColors.accent : Color.white)
                .lineLimit(1)

            if isHD {
                Text("HD")
                    .font(EPGMetrics.font(11, .bold))
                    .foregroundStyle(isSelected ? Color.white : EPGColors.accent)
                    .padding(.horizontal, EPGMetrics.s(5))
                    .padding(.vertical, EPGMetrics.s(1.5))
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: EPGMetrics.s(3)))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, EPGMetrics.s(14))
        .frame(width: width, height: height, alignment: .leading)
        .background(isSelected ? Color.white.opacity(0.12) : EPGColors.column)
        .overlay(alignment: .leading) {
            // Aktive Zeilenauswahl: dezente Pille am linken Rand als Overlay,
            // damit das Senderlogo und die Sendernummer beim Weiterspringen nicht nach rechts verrutschen
            if isSelected {
                Capsule()
                    .fill(EPGColors.accent)
                    .frame(width: EPGMetrics.s(3.5), height: height * 0.45)
                    .padding(.leading, EPGMetrics.s(3))
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
        ZStack(alignment: .topLeading) {
            if isSelected {
                Rectangle().fill(EPGColors.selectedRow)
            }
            if items.isEmpty {
                Text("Keine Programmdaten")
                    .font(EPGMetrics.font(14, .regular))
                    .foregroundStyle(EPGColors.tertiaryText)
                    .padding(.horizontal, 14)
                    .frame(height: height)
            }
            ForEach(items) { item in
                if let prog = item.program {
                    ProgramBlockView(prog: prog,
                                     isLive: item.id == liveID,
                                     isFocused: item.id == focusedID,
                                     progress: item.id == liveID ? progress : 0,
                                     width: item.width)
                        .frame(height: height - 6)
                        #if os(macOS)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            onDoubleClickProgram?()
                        }
                        .onTapGesture {
                            onSelectProgram?(prog)
                        }
                        #endif
                        .offset(x: item.x, y: 3)
                        .zIndex(item.id == focusedID ? 1 : 0)
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

    var body: some View {
        let step: TimeInterval = 30 * 60
        let first = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 / step) * step)
        let count = Int(ceil(Double(width / pointsPerMinute) / 30)) + 2
        ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { index in
                let date = first.addingTimeInterval(Double(index) * step)
                let isFullHour = Calendar.current.component(.minute, from: date) == 0
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.white.opacity(isFullHour ? 0.7 : 0.3))
                        .frame(width: isFullHour ? 2 : 1, height: isFullHour ? 14 : 8)
                    if isFullHour && Calendar.current.component(.hour, from: date) == 0 {
                        Text(Self.dayName(date))
                            .font(EPGMetrics.font(13, .bold))
                            .foregroundStyle(EPGColors.accent)
                    }
                    Text(EPGOverviewView.formatTime(date))
                        .font(EPGMetrics.font(isFullHour ? 15 : 13, isFullHour ? .bold : .medium))
                        .foregroundStyle(Color.white.opacity(isFullHour ? 0.95 : 0.5))
                }
                .frame(width: 30 * pointsPerMinute, height: height, alignment: .leading)
                .offset(x: CGFloat(date.timeIntervalSince(start) / 60) * pointsPerMinute)
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
    let progress: Double
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Text("\(EPGOverviewView.formatTime(prog.startDate)) – \(EPGOverviewView.formatTime(prog.endDate))")
                    .font(EPGMetrics.font(13, .bold))
                    .foregroundStyle(isLive ? EPGColors.accent : (isFocused ? Color.white : EPGColors.secondaryText))
                    .lineLimit(1)
            }

            Text(prog.title)
                .font(EPGMetrics.font(16, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            if !isLive, width >= EPGMetrics.s(140), let sub = prog.subtitle ?? prog.description, !sub.isEmpty {
                Text(sub)
                    .font(EPGMetrics.font(13, .regular))
                    .foregroundStyle(isFocused ? Color.white.opacity(0.85) : EPGColors.tertiaryText)
                    .lineLimit(1)
            }

            if isLive {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(EPGColors.accent)
                            .frame(width: max(geo.size.width * progress, 5))
                    }
                }
                .frame(height: 3)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.white.opacity(isLive ? 0.22 : 0.16) : (isLive ? EPGColors.liveCell : EPGColors.cell))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.white : (isLive ? EPGColors.accent.opacity(0.35) : EPGColors.cellBorder),
                              lineWidth: isFocused ? 2 : 1)
        )
        // Fokus wie im System: angewählte Kachel hebt sich leicht an.
        .scaleEffect(isFocused ? 1.03 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: isFocused ? 10 : 0, y: isFocused ? 4 : 0)
        .animation(.easeOut(duration: 0.12), value: isFocused)
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

/// Maße der Programmübersicht. Auf dem Apple TV aus mehreren Metern Abstand lesbar, daher
/// deutlich größer als auf dem Mac.
enum EPGMetrics {
    #if os(tvOS)
    static let k: CGFloat = 1.6
    static let previewSize = CGSize(width: 384, height: 216)
    #else
    static let k: CGFloat = 0.85
    static let previewSize = CGSize(width: 256, height: 144)
    #endif

    static func s(_ value: CGFloat) -> CGFloat { value * k }

    /// Apple TV: mindestens 23 pt (Apple-Richtlinien).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        #if os(tvOS)
        .system(size: max(size * k, UI.minimumFontSize), weight: weight)
        #else
        .system(size: size * k, weight: weight)
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
