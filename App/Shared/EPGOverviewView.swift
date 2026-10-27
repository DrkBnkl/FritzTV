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
    /// Eigene Beobachtung: Änderungen am Suchlauf sollen die Kopfzeile sofort aktualisieren.
    @ObservedObject private var scanner: BackgroundEPGScanner
    @ObservedObject private var nav: EPGNavigation

    // Timeline-Konfiguration; alle Maße über EPGMetrics (auf dem Apple TV deutlich größer)
    private let pointsPerMinute: CGFloat = EPGMetrics.s(4.0)
    private let totalHours: Int = 24
    private let rowHeight: CGFloat = EPGMetrics.s(68)
    private let rulerHeight: CGFloat = EPGMetrics.s(40)
    private let channelColumnWidth: CGFloat = EPGMetrics.s(250)

    /// Beginn des Zeitstrahls (volle Stunde, mindestens 30 Minuten vor jetzt).
    @State private var windowStart: Date = EPGOverviewView.makeWindowStart()
    /// Kacheln je Senderplatz, neu berechnet nur bei neuen Programmdaten.
    @State private var rowItems: [Int: [TimelineItem]] = [:]
    /// Erste sichtbare Zeile (Index in `entries`).
    @State private var topIndex = 0
    /// Anzahl ganz sichtbarer Zeilen, aus der Höhe des Rasters.
    @State private var visibleRows = 6
    @State private var lastRebuild = Date.distantPast
    @State private var rebuildPending = false

    init(model: AppModel, player: PlayerController) {
        self.model = model
        self.player = player
        self.scanner = model.epgScanner
        self.nav = model.epgNav
    }

    private var entries: [LineupEntry] {
        model.lineup?.entries ?? []
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
        let earlier = now.addingTimeInterval(-30 * 60)
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
        .background(EPGColors.background.ignoresSafeArea())
        // Keine eigene Fokus- oder Tastensteuerung: Fernbedienung und Tastatur laufen wie bei der
        // Senderliste über `AppModel.handle`. Zwei konkurrierende Steuerungen führten dazu, dass
        // Hoch/Runter im Hintergrund den Live-Sender wechselte statt die Auswahl zu bewegen.
        .preferredColorScheme(.dark)
        .onAppear {
            rebuildRows()
            topIndex = clampedTop(for: selectedIndex, current: selectedIndex - 2)
        }
        .onChange(of: player.epgRevision) { _, _ in scheduleRebuild() }
        .onChange(of: model.lineup?.entries.count) { _, _ in rebuildRows() }
        .onChange(of: nav.selectedKey) { _, _ in
            let newTop = clampedTop(for: selectedIndex, current: topIndex)
            if newTop != topIndex {
                withAnimation(.easeOut(duration: 0.18)) { topIndex = newTop }
            }
        }
    }

    /// Blättert erst, wenn die Auswahl die zweite Zeile vom Rand erreicht.
    private func clampedTop(for index: Int, current: Int) -> Int {
        let count = entries.count
        let visible = max(visibleRows, 3)
        var top = current
        if index < top + 1 { top = index - 1 }
        if index > top + visible - 2 { top = index - visible + 2 }
        return max(0, min(top, max(0, count - visible)))
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
        let start = Self.makeWindowStart()
        let end = start.addingTimeInterval(Double(totalHours) * 3600)
        var items: [Int: [TimelineItem]] = [:]
        for entry in entries {
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
                Text(headerDateString)
                    .font(EPGMetrics.font(20, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if scanner.isScanning {
                    HStack(spacing: 6) {
                        #if os(macOS)
                        ProgressView().controlSize(.small)
                        #else
                        // `controlSize` gibt es auf tvOS nicht.
                        ProgressView().scaleEffect(0.6)
                        #endif
                        Text("Lade Programmdaten\(scanner.currentScanningChannel.map { " (\($0))" } ?? "") … · Live-Bild pausiert")
                            .font(EPGMetrics.font(14, .regular))
                            .foregroundStyle(EPGColors.secondaryText)
                    }
                }

                #if os(macOS)
                // Knöpfe nur für die Maus; auf dem Apple TV: Zurück schließt.
                HStack(spacing: 12) {
                    headerButton("Jetzt") {
                        withAnimation(.easeInOut(duration: 0.25)) { model.epgCursorTime = nil }
                    }
                    headerButton(scanner.isScanning ? "Laden abbrechen" : "Programmdaten aller Sender laden") {
                        model.toggleManualEPGScan()
                    }
                    .help("Das Live-Bild pausiert solange (Leertaste)")
                    headerButton("Schließen") { model.closeEPGOverview() }
                        .help("Programmübersicht schließen (Esc)")
                }
                #else
                Text(scanner.isScanning
                     ? "\(UI.playPause): Laden abbrechen · \(UI.back): schließen"
                     : "\(UI.upDown): Sender · \(UI.leftRight): spätere Sendungen · \(UI.select): umschalten · \(UI.playPause): Programmdaten laden · \(UI.back): schließen")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .font(EPGMetrics.font(14, .medium))
                    .foregroundStyle(EPGColors.tertiaryText)
                #endif
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
    }

    // MARK: - Raster

    private var timelineBody: some View {
        let now = Date()
        let focus = focusTime
        let offset = horizontalOffset
        let all = entries
        let selected = selectedChannelNumber
        let top = topIndex
        let first = max(0, top - 2)
        let last = min(all.count, top + visibleRows + 3)

        return GeometryReader { geo in
            let timelineWidth = max(0, geo.size.width - channelColumnWidth)
            let rowsHeight = max(0, geo.size.height - rulerHeight)
            VStack(spacing: 0) {
                rulerRow(now: now, offset: offset, timelineWidth: timelineWidth)
                ZStack(alignment: .topLeading) {
                    ForEach(first..<max(first, last), id: \.self) { index in
                        let entry = all[index]
                        let isSelected = entry.number == selected
                        let items = rowItems[entry.number] ?? []
                        row(entry: entry, items: items, isSelected: isSelected,
                            focus: focus, now: now, offset: offset, timelineWidth: timelineWidth)
                            .offset(y: CGFloat(index - top) * rowHeight)
                    }
                    nowLine(now: now, offset: offset)
                }
                .frame(width: geo.size.width, height: rowsHeight, alignment: .topLeading)
                .clipped()
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear { updateVisibleRows(height: rowsHeight) }
            .onChange(of: rowsHeight) { _, height in updateVisibleRows(height: height) }
        }
        .animation(.easeInOut(duration: 0.25), value: nav.cursorTime)
    }

    private func updateVisibleRows(height: CGFloat) {
        let rows = max(3, Int(height / rowHeight))
        if rows != visibleRows {
            visibleRows = rows
            topIndex = clampedTop(for: selectedIndex, current: topIndex)
        }
    }

    private func row(entry: LineupEntry, items: [TimelineItem], isSelected: Bool,
                     focus: Date, now: Date, offset: CGFloat, timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ChannelCell(number: entry.number,
                        name: entry.group.displayName,
                        isCurrent: entry.number == model.currentNumber,
                        isSelected: isSelected,
                        width: channelColumnWidth,
                        height: rowHeight)
                .equatable()

            TimelineRow(items: items,
                        focusedID: isSelected ? Self.programID(in: items, at: focus) : nil,
                        liveID: Self.programID(in: items, at: now),
                        isSelected: isSelected,
                        progress: Self.liveProgress(in: items, at: now),
                        width: totalTimelineWidth,
                        height: rowHeight)
                .equatable()
                .offset(x: -offset)
                .frame(width: timelineWidth, height: rowHeight, alignment: .leading)
                .clipped()
        }
        .frame(width: channelColumnWidth + timelineWidth, height: rowHeight, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EPGColors.line.opacity(0.5)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.tuneFromEPG(key: AppModel.key(entry)) }
    }

    /// Zeitleiste oben; bleibt beim senkrechten Blättern stehen.
    private func rulerRow(now: Date, offset: CGFloat, timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let cursor = nav.cursorTime {
                    Text("ab \(Self.formatTime(cursor))")
                        .font(EPGMetrics.font(15, .bold))
                        .foregroundStyle(EPGColors.accent)
                } else {
                    Text("Jetzt")
                        .font(EPGMetrics.font(15, .bold))
                        .foregroundStyle(EPGColors.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: channelColumnWidth, height: rulerHeight, alignment: .leading)
            .background(EPGColors.ruler)

            TimeRuler(start: windowStart, hours: totalHours, pointsPerMinute: pointsPerMinute, height: rulerHeight)
                .equatable()
                .offset(x: -offset)
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

/// Blautöne der Programmübersicht.
enum EPGColors {
    static let background = Color(red: 0.03, green: 0.06, blue: 0.12)
    static let header = Color(red: 0.05, green: 0.09, blue: 0.17)
    static let column = Color(red: 0.04, green: 0.08, blue: 0.15)
    static let ruler = Color(red: 0.06, green: 0.11, blue: 0.21)
    static let line = Color(red: 0.25, green: 0.38, blue: 0.60).opacity(0.45)
    static let cell = Color(red: 0.13, green: 0.22, blue: 0.40).opacity(0.55)
    static let cellBorder = Color(red: 0.45, green: 0.62, blue: 0.95).opacity(0.18)
    static let liveCell = Color(red: 0.13, green: 0.33, blue: 0.66).opacity(0.75)
    static let focusCell = Color(red: 0.22, green: 0.50, blue: 0.95)
    static let selectedRow = Color(red: 0.30, green: 0.50, blue: 0.90).opacity(0.16)
    static let accent = Color(red: 0.50, green: 0.78, blue: 1.0)
    static let nowLine = Color(red: 0.55, green: 0.85, blue: 1.0)
    static let secondaryText = Color(red: 0.70, green: 0.78, blue: 0.90)
    static let tertiaryText = Color(red: 0.55, green: 0.63, blue: 0.76)
}

// MARK: - Zeilenbausteine

private struct ChannelCell: View, Equatable {
    let number: Int
    let name: String
    let isCurrent: Bool
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(EPGMetrics.font(18, .bold))
                .foregroundStyle(isCurrent ? EPGColors.accent : EPGColors.tertiaryText)
                .frame(width: EPGMetrics.s(34), alignment: .trailing)

            ChannelLogoView(channelName: name, height: EPGMetrics.s(26), maxWidth: EPGMetrics.s(46))

            Text(name)
                .font(EPGMetrics.font(17, .semibold))
                .foregroundStyle(isCurrent ? EPGColors.accent : Color.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isCurrent {
                Text("LÄUFT")
                    .font(EPGMetrics.font(11, .heavy))
                    .foregroundStyle(EPGColors.background)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(EPGColors.accent, in: Capsule())
            }
        }
        .padding(.horizontal, EPGMetrics.s(12))
        .frame(width: width, height: height, alignment: .leading)
        .background(isSelected ? EPGColors.focusCell.opacity(0.35) : EPGColors.column)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(EPGColors.accent).frame(width: 4)
            }
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isSelected {
                Rectangle().fill(EPGColors.selectedRow)
            }
            if items.isEmpty {
                Text("Keine Programmdaten – \(UI.playPause) lädt sie")
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
                        .offset(x: item.x, y: 3)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

private struct TimeRuler: View, Equatable {
    let start: Date
    let hours: Int
    let pointsPerMinute: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<(hours * 2), id: \.self) { index in
                let date = start.addingTimeInterval(Double(index * 30 * 60))
                let isFullHour = index % 2 == 0
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
            }
        }
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
                    .foregroundStyle(isFocused ? Color.white : (isLive ? EPGColors.accent : EPGColors.secondaryText))
                    .lineLimit(1)
                if isLive {
                    Text("LIVE")
                        .font(EPGMetrics.font(11, .heavy))
                        .foregroundStyle(EPGColors.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(EPGColors.accent, in: Capsule())
                }
            }

            Text(prog.title)
                .font(EPGMetrics.font(16, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            if width >= EPGMetrics.s(140), let sub = prog.subtitle ?? prog.description, !sub.isEmpty {
                Text(sub)
                    .font(EPGMetrics.font(13, .regular))
                    .foregroundStyle(isFocused ? Color.white.opacity(0.85) : EPGColors.tertiaryText)
                    .lineLimit(1)
            }

            if isLive {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(EPGColors.accent)
                            .frame(width: max(geo.size.width * progress, 5))
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? EPGColors.focusCell : (isLive ? EPGColors.liveCell : EPGColors.cell))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.white.opacity(0.9) : (isLive ? EPGColors.accent.opacity(0.7) : EPGColors.cellBorder),
                              lineWidth: isFocused ? 2 : 1)
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

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * k, weight: weight)
    }
}

/// Auswahl in der Programmübersicht (siehe `AppModel.epgNav`).
@MainActor
final class EPGNavigation: ObservableObject {
    @Published var selectedKey: String?
    @Published var cursorTime: Date?
}
