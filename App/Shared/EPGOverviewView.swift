import SwiftUI
import FritzTVKit

/// EPG-Programmübersicht mit horizontaler Timeline (Zeitstrahl) über alle Sender.
struct EPGOverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var selectedChannelNumber: Int?
    @FocusState private var isFocused: Bool
    @State private var sheetKeyMonitor: Any?

    // Timeline-Konfiguration
    private let pointsPerMinute: CGFloat = 3.5
    private let totalHours: Int = 24
    private let rowHeight: CGFloat = 58
    private let rulerHeight: CGFloat = 38
    private let channelColumnWidth: CGFloat = 210

    init(model: AppModel, player: PlayerController, scanner: BackgroundEPGScanner? = nil) {
        self.model = model
        self.player = player
        _selectedChannelNumber = State(initialValue: model.currentNumber)
    }

    private var entries: [LineupEntry] {
        model.lineup?.entries ?? []
    }

    private var timelineStart: Date {
        let now = Date()
        let thirtyMinsAgo = now.addingTimeInterval(-30 * 60)
        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: thirtyMinsAgo)
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? now
    }

    private var timelineEnd: Date {
        timelineStart.addingTimeInterval(Double(totalHours) * 3600)
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(totalHours * 60) * pointsPerMinute
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM · HH:mm 'Uhr'"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    headerBar(proxy: proxy)
                    Divider().background(Color.white.opacity(0.15))
                    timelineBody(proxy: proxy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
                .task {
                    let num = selectedChannelNumber ?? model.currentNumber
                    proxy.scrollTo("channel_\(num)", anchor: .center)
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("timeline_now", anchor: .leading)
                    }
                }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear {
                isFocused = true
                if selectedChannelNumber == nil {
                    selectedChannelNumber = model.currentNumber
                }
                #if os(macOS)
                if sheetKeyMonitor == nil {
                    sheetKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        switch event.keyCode {
                        case 126: // Up
                            selectPreviousChannel()
                            return nil
                        case 125: // Down
                            selectNextChannel()
                            return nil
                        case 36, 76: // Return / Enter
                            tuneSelected()
                            return nil
                        case 53: // Escape
                            dismiss()
                            return nil
                        default:
                            return event
                        }
                    }
                }
                #endif
            }
            .onDisappear {
                #if os(macOS)
                if let sheetKeyMonitor {
                    NSEvent.removeMonitor(sheetKeyMonitor)
                    self.sheetKeyMonitor = nil
                }
                #endif
            }
            #if os(macOS)
            .onKeyPress(.upArrow) {
                selectPreviousChannel()
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectNextChannel()
                return .handled
            }
            .onKeyPress(.return) {
                tuneSelected()
                return .handled
            }
            .onKeyPress(.space) {
                tuneSelected()
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            #elseif os(tvOS)
            .onMoveCommand { direction in
                switch direction {
                case .up: selectPreviousChannel()
                case .down: selectNextChannel()
                default: break
                }
            }
            .onPlayPauseCommand {
                tuneSelected()
            }
            .onExitCommand {
                dismiss()
            }
            #endif
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header Bar

    private func headerBar(proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Programmübersicht")
                    .font(UI.font(26, .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(headerDateString)
                    .font(UI.font(16, .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if model.epgScanner.isScanning, let ch = model.epgScanner.currentScanningChannel {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Lade EPG (\(ch)) …")
                        .font(UI.font(13, .regular))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
            }

            // Schnell-Sprung zu "Jetzt"
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("timeline_now", anchor: .leading)
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("Jetzt")
                        .font(UI.font(15, .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)

            Text("Esc: Schließen")
                .font(UI.font(13, .regular))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    // MARK: - Timeline Body (Vertical + Horizontal Scroll)

    private func timelineBody(proxy: ScrollViewProxy) -> some View {
        let _ = player.epgRevision
        let now = Date()
        let start = timelineStart
        let end = timelineEnd

        return ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // Linke fixierte Senderspalte
                VStack(alignment: .leading, spacing: 0) {
                    // Eckbereich in Höhe des Zeitstrahls
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("Sender")
                            .font(UI.font(13, .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .frame(width: channelColumnWidth, height: rulerHeight, alignment: .leading)
                    .background(Color(red: 0.09, green: 0.09, blue: 0.12))

                    Divider().background(Color.white.opacity(0.12))

                    ForEach(entries) { entry in
                        channelHeaderCell(entry)
                            .id("channel_\(entry.number)")
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
                .frame(width: channelColumnWidth)
                .background(Color(red: 0.07, green: 0.07, blue: 0.09))

                Divider().background(Color.white.opacity(0.18))

                // Rechter horizontal scrollbarer Zeitstrahl
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Hintergrund-Gitter (alle 30 Min)
                        timelineGridBackground

                        // Vertikale "Jetzt"-Linie
                        nowIndicator(in: now)

                        // Inhalt: Zeitleiste oben + Zeilen pro Sender
                        VStack(alignment: .leading, spacing: 0) {
                            timeRuler
                                .frame(height: rulerHeight)

                            Divider().background(Color.white.opacity(0.12))

                            ForEach(entries) { entry in
                                let items = buildTimelineItems(for: entry, start: start, end: end)
                                channelTimelineRow(entry: entry, items: items, now: now)
                                    .frame(height: rowHeight)
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .frame(width: totalTimelineWidth)
                }
            }
        }
    }

    // MARK: - Channel Header Cell

    private func channelHeaderCell(_ entry: LineupEntry) -> some View {
        let isCurrent = entry.number == model.currentNumber
        let isSelected = selectedChannelNumber == entry.number

        return HStack(spacing: 8) {
            Text("\(entry.number)")
                .font(UI.font(14, .bold))
                .foregroundStyle(isCurrent ? UI.accent : Color.white.opacity(0.45))
                .frame(width: 26, alignment: .trailing)

            ChannelLogoView(channelName: entry.group.displayName, height: 22, maxWidth: 36)

            Text(entry.group.displayName)
                .font(UI.font(14, .semibold))
                .foregroundStyle(isCurrent ? UI.accent : Color.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isCurrent {
                Text("LÄUFT")
                    .font(UI.font(9, .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(UI.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .frame(width: channelColumnWidth, height: rowHeight, alignment: .leading)
        .background(
            isSelected ? Color.white.opacity(0.12) : (isCurrent ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedChannelNumber = entry.number
            model.tune(to: entry.number)
            dismiss()
        }
    }

    // MARK: - Channel Timeline Row

    private func channelTimelineRow(entry: LineupEntry, items: [TimelineItem], now: Date) -> some View {
        HStack(spacing: 3) {
            if items.isEmpty || (items.count == 1 && items[0].isGap) {
                HStack {
                    Text("Keine Programmdaten empfangen")
                        .font(UI.font(12, .regular))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.horizontal, 12)
                    Spacer()
                }
                .frame(width: 300, height: rowHeight - 8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 0)
            } else {
                ForEach(items) { item in
                    if let prog = item.program {
                        ProgramBlockView(
                            prog: prog,
                            isLive: prog.isLive(at: now),
                            width: item.width,
                            now: now
                        )
                        .onTapGesture {
                            selectedChannelNumber = entry.number
                            model.tune(to: entry.number)
                            dismiss()
                        }
                    } else {
                        Spacer(minLength: item.width)
                            .frame(width: item.width)
                    }
                }
            }
        }
        .frame(width: totalTimelineWidth, height: rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedChannelNumber = entry.number
            model.tune(to: entry.number)
            dismiss()
        }
    }

    // MARK: - Time Ruler (Oberste Zeitleiste)

    private var timeRuler: some View {
        HStack(spacing: 0) {
            ForEach(0..<(totalHours * 2), id: \.self) { halfHourIndex in
                let minuteOffset = halfHourIndex * 30
                let date = timelineStart.addingTimeInterval(Double(minuteOffset * 60))
                let isFullHour = (halfHourIndex % 2 == 0)
                let isMidnight = Calendar.current.component(.hour, from: date) == 0 && isFullHour

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 4) {
                        Rectangle()
                            .fill(isFullHour ? Color.white.opacity(0.7) : Color.white.opacity(0.3))
                            .frame(width: isFullHour ? 2 : 1, height: isFullHour ? 11 : 6)

                        if isMidnight {
                            Text(dayName(from: date))
                                .font(UI.font(11, .bold))
                                .foregroundStyle(UI.accent)
                        }

                        Text(Self.formatTime(date))
                            .font(UI.font(isFullHour ? 12 : 11, isFullHour ? .bold : .regular))
                            .foregroundStyle(isFullHour ? Color.white.opacity(0.9) : Color.white.opacity(0.45))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .frame(width: 30 * pointsPerMinute, height: rulerHeight, alignment: .topLeading)
            }
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.12))
    }

    // MARK: - Background Grid

    private var timelineGridBackground: some View {
        HStack(spacing: 0) {
            ForEach(0..<(totalHours * 2), id: \.self) { halfHourIndex in
                let isFullHour = (halfHourIndex % 2 == 0)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 30 * pointsPerMinute)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(isFullHour ? Color.white.opacity(0.06) : Color.white.opacity(0.025))
                            .frame(width: 1)
                    }
            }
        }
    }

    // MARK: - Now Indicator (Rote Zeitlinie)

    @ViewBuilder
    private func nowIndicator(in now: Date) -> some View {
        let offsetMinutes = now.timeIntervalSince(timelineStart) / 60.0
        let xPos = CGFloat(offsetMinutes) * pointsPerMinute
        if xPos >= 0 && xPos <= totalTimelineWidth {
            ZStack(alignment: .topLeading) {
                // Rote vertikale Linie durch alle Senderzeilen
                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: xPos - 1)

                // Roter Badge im Zeitstrahl-Kopf
                HStack(spacing: 4) {
                    Circle().fill(Color.white).frame(width: 5, height: 5)
                    Text(Self.formatTime(now))
                        .font(UI.font(10, .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red, in: Capsule())
                .shadow(color: .black.opacity(0.5), radius: 3)
                .offset(x: max(0, xPos - 26), y: 4)
                .id("timeline_now")
            }
        }
    }

    // MARK: - Timeline Item Computation

    struct TimelineItem: Identifiable {
        let id: String
        let isGap: Bool
        let program: EPGProgram?
        let width: CGFloat
    }

    private func buildTimelineItems(for entry: LineupEntry, start: Date, end: Date) -> [TimelineItem] {
        let schedule = player.epgStore.schedule(forChannelNames: entry.group.epgNames)
        let rawPrograms = (schedule?.programs ?? []).sorted { $0.startDate < $1.startDate }

        var items: [TimelineItem] = []
        var cursor = start

        for prog in rawPrograms {
            guard prog.endDate > start else { continue }
            guard prog.startDate < end else { break }

            let effectiveStart = max(prog.startDate, cursor)
            let effectiveEnd = min(prog.endDate, end)
            guard effectiveEnd > effectiveStart else { continue }

            // Lücke vor diesem Programm
            if effectiveStart > cursor {
                let gapSeconds = effectiveStart.timeIntervalSince(cursor)
                let gapWidth = CGFloat(gapSeconds / 60.0) * pointsPerMinute
                if gapWidth > 2 {
                    items.append(TimelineItem(
                        id: "gap_\(entry.number)_\(cursor.timeIntervalSince1970)",
                        isGap: true,
                        program: nil,
                        width: gapWidth
                    ))
                }
            }

            // Programm-Kachel
            let cardSeconds = effectiveEnd.timeIntervalSince(effectiveStart)
            let cardWidth = max(26, CGFloat(cardSeconds / 60.0) * pointsPerMinute - 3)

            items.append(TimelineItem(
                id: prog.id,
                isGap: false,
                program: prog,
                width: cardWidth
            ))

            cursor = effectiveEnd
        }

        if cursor < end {
            let remainingSeconds = end.timeIntervalSince(cursor)
            let remainingWidth = CGFloat(remainingSeconds / 60.0) * pointsPerMinute
            if remainingWidth > 2 {
                items.append(TimelineItem(
                    id: "gap_end_\(entry.number)_\(cursor.timeIntervalSince1970)",
                    isGap: true,
                    program: nil,
                    width: remainingWidth
                ))
            }
        }

        return items
    }

    // MARK: - Navigation Helpers

    private func selectNextChannel() {
        guard !entries.isEmpty else { return }
        if let current = selectedChannelNumber,
           let index = entries.firstIndex(where: { $0.number == current }) {
            let nextIndex = min(index + 1, entries.count - 1)
            selectedChannelNumber = entries[nextIndex].number
        } else {
            selectedChannelNumber = entries.first?.number
        }
    }

    private func selectPreviousChannel() {
        guard !entries.isEmpty else { return }
        if let current = selectedChannelNumber,
           let index = entries.firstIndex(where: { $0.number == current }) {
            let prevIndex = max(index - 1, 0)
            selectedChannelNumber = entries[prevIndex].number
        } else {
            selectedChannelNumber = entries.first?.number
        }
    }

    private func tuneSelected() {
        guard let num = selectedChannelNumber else { return }
        model.tune(to: num)
        dismiss()
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dayName(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

// MARK: - ProgramBlockView

private struct ProgramBlockView: View {
    let prog: EPGProgram
    let isLive: Bool
    let width: CGFloat
    let now: Date
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                Text("\(EPGOverviewView.formatTime(prog.startDate)) – \(EPGOverviewView.formatTime(prog.endDate))")
                    .font(UI.font(11, .semibold))
                    .foregroundStyle(isLive ? UI.accent : Color.white.opacity(0.65))
                    .lineLimit(1)

                if isLive {
                    Text("LIVE")
                        .font(UI.font(9, .heavy))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(UI.accent, in: Capsule())
                }
            }

            Text(prog.title)
                .font(UI.font(13, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            if width >= 140, let sub = prog.subtitle ?? prog.description, !sub.isEmpty {
                Text(sub)
                    .font(UI.font(11, .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            if isLive {
                GeometryReader { geo in
                    let progress = prog.progress(at: now)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(UI.accent)
                            .frame(width: max(geo.size.width * progress, 4))
                    }
                }
                .frame(height: 3)
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    isHovered
                        ? Color.white.opacity(0.18)
                        : (isLive ? Color(red: 0.85, green: 0.42, blue: 0.05).opacity(0.25) : Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    isLive ? UI.accent.opacity(0.8) : (isHovered ? Color.white.opacity(0.4) : Color.white.opacity(0.1)),
                    lineWidth: isLive ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltipText)
        #endif
    }

    private var tooltipText: String {
        var lines: [String] = []
        lines.append(prog.title)
        lines.append("\(EPGOverviewView.formatTime(prog.startDate)) – \(EPGOverviewView.formatTime(prog.endDate)) (\(Int(prog.duration / 60)) Min.)")
        if let sub = prog.subtitle, !sub.isEmpty {
            lines.append(sub)
        }
        if let desc = prog.description, !desc.isEmpty, desc != prog.subtitle {
            lines.append(desc)
        }
        return lines.joined(separator: "\n\n")
    }
}
