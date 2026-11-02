import SwiftUI
import FritzTVKit

// MARK: Bausteine

/// Listenzeilen ohne Druck-Darstellung: Auf dem Apple TV zeigten beim Klick (der über
/// `AppModel.handle` läuft) alle Zeilen kurz den gedrückten, weißen Zustand.
struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension View {
    /// Fokus wie im System (Apple-Richtlinien): das gewählte Element hebt sich leicht an –
    /// etwas größer, mit Schatten, kurz animiert.
    func focusLift(_ focused: Bool, scale: CGFloat = 1.03) -> some View {
        self
            .scaleEffect(focused ? scale : 1)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: focused ? 12 : 0, y: focused ? 6 : 0)
            .zIndex(focused ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct Badge: View {
    let text: String
    var dark = false

    var body: some View {
        Text(text)
            .font(UI.font(22, .bold))
            .foregroundStyle(dark ? Color.black : UI.text)
            .padding(.horizontal, UI.s(14))
            .padding(.vertical, UI.s(4))
            .overlay(RoundedRectangle(cornerRadius: UI.s(8)).stroke(dark ? Color.black : UI.text, lineWidth: UI.s(2)))
    }
}

private struct BottomPanel<Content: View>: View {
    @Environment(\.windowSize) private var windowSize
    @ViewBuilder let content: Content

    private var isCompact: Bool {
        #if os(macOS)
        return windowSize.height < 450
        #else
        return false
        #endif
    }

    var body: some View {
        VStack {
            Spacer()
            content
                .padding(.horizontal, isCompact ? 16 : UI.s(48))
                .padding(.vertical, isCompact ? 12 : UI.s(36))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { PanelBackground(cornerRadius: isCompact ? 16 : UI.s(32)) }
                .padding(.horizontal, isCompact ? 10 : UI.s(16))
                .padding(.bottom, isCompact ? 8 : 0)
        }
        // Unten genau am sicheren Bereich (60 pt vom Bildrand, Apple-Richtlinien): so tief wie
        // möglich, ohne dass ein Fernseher mit Überscan etwas abschneidet.
    }
}

/// Tafel am oberen Rand (Info, wie die Info-Reiter des Apple-Players: Wischen nach unten).
private struct TopPanel<Content: View>: View {
    var onTapOutside: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack {
            content
                .padding(.horizontal, UI.s(48))
                .padding(.vertical, UI.s(36))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { PanelBackground(cornerRadius: UI.s(32)) }
                .padding(.horizontal, UI.s(16))
            Spacer()
                #if os(macOS)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onTapOutside?() }
                #endif
        }
    }
}

/// Durchscheinender Hintergrund für Tafeln über dem Video (Apple: Overlays zurückhaltend und
/// eher durchscheinend; dichtes Material plus Abdunklung für Lesbarkeit bei hellem Bild).
struct PanelBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.regularMaterial)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(UI.panelDim))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: UI.s(1))
            )
            .environment(\.colorScheme, .dark)
    }
}

struct StatusCard: View {
    let title: String
    let message: String?
    let hint: String?
    let busy: Bool

    var body: some View {
        VStack(spacing: UI.s(20)) {
            if busy { ProgressView() }
            Text(title).font(UI.font(40, .bold))
            if let message {
                Text(message).font(UI.font(28)).foregroundStyle(UI.secondary).multilineTextAlignment(.center)
            }
            if let hint {
                Text(hint).font(UI.font(24)).foregroundStyle(UI.secondary).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(UI.text)
        .padding(UI.s(56))
        .frame(maxWidth: UI.s(1000))
        .background { PanelBackground(cornerRadius: UI.s(28)) }
    }
}

// MARK: Infoleiste nach dem Umschalten

struct InfoBanner: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.windowSize) private var windowSize

    private var isCompact: Bool {
        #if os(macOS)
        return windowSize.width < 760
        #else
        return false
        #endif
    }

    var body: some View {
        if let entry = model.currentEntry {
            BottomPanel {
                HStack(spacing: isCompact ? 16 : UI.s(48)) {
                    VStack(spacing: UI.s(4)) {
                        Text("\(entry.number)").font(UI.font(isCompact ? 56 : 96, .heavy))
                        ChannelLogoView(channelName: entry.group.displayName, height: isCompact ? 28 : UI.s(44), maxWidth: isCompact ? 90 : UI.s(180))
                        Text(entry.group.displayName).font(UI.font(isCompact ? 20 : 26, .semibold)).lineLimit(1)
                    }
                    .frame(width: isCompact ? 95 : UI.s(220))

                    VStack(alignment: .leading, spacing: isCompact ? 4 : UI.s(8)) {
                        let current = player.displayedProgram
                        let timeString = current.map { "\(Self.formatTime($0.startDate)) – \(Self.formatTime($0.endDate))" } ?? ""
                        HStack(spacing: isCompact ? 8 : UI.s(16)) {
                            Text("JETZT").font(UI.font(isCompact ? 18 : 24, .semibold)).foregroundStyle(UI.secondary)
                            if !timeString.isEmpty {
                                Text(timeString).font(UI.font(isCompact ? 18 : 24, .semibold)).foregroundStyle(UI.accent)
                            }
                        }
                        Text(current?.title ?? player.nowPlaying ?? "Keine Programminformation")
                            .font(UI.font(isCompact ? 26 : 40, .bold))
                            .lineLimit(2)

                        if let next = player.displayedNextProgram {
                            Text("Danach ab \(Self.formatTime(next.startDate)): \(next.title)")
                                .font(UI.font(isCompact ? 18 : 24))
                                .foregroundStyle(UI.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: isCompact ? 12 : UI.s(24))

                    VStack(alignment: .trailing, spacing: isCompact ? 8 : UI.s(16)) {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(context.date, format: .dateTime.hour().minute()).font(UI.font(isCompact ? 30 : 44, .semibold))
                        }
                        Badge(text: player.channel?.isHD == false ? "SD" : "HD")
                    }
                }
                .foregroundStyle(UI.text)
                #if os(macOS)
                .contentShape(Rectangle())
                .onTapGesture { model.openInfoPanel() }
                .help("Klicken für ausführliche Sendungsinfo")
                #endif
            }
        }
    }

    static func formatTime(_ date: Date) -> String {
        UI.timeFormatter.string(from: date)
    }
}

// MARK: Timeshift

struct TimeshiftBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let behind = player.currentBehind
            BottomPanel {
                VStack(alignment: .leading, spacing: UI.s(18)) {
                    HStack {
                        Text("\(model.currentEntry?.number ?? 0) \(model.currentEntry?.group.displayName ?? "")")
                            .font(UI.font(32, .bold))
                        if let title = player.displayedProgram?.title ?? player.nowPlaying {
                            Text("· \(title)").font(UI.font(32)).lineLimit(1)
                        }
                        Spacer()
                        Text(player.pausedSince != nil ? "Angehalten · \(Self.format(behind)) hinter Live"
                                                       : "\(Self.format(behind)) hinter Live")
                            .font(UI.font(32, .bold))
                            .foregroundStyle(UI.accent)
                    }
                    GeometryReader { geo in
                        let maxSeconds = Double(max(model.settings.timeshiftMinutes, 1) * 60)
                        let share = min(max(behind / maxSeconds, 0), 1)
                        ZStack(alignment: .trailing) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(Color.white.opacity(0.5))
                                .frame(width: max(geo.size.width * share, UI.s(8)))
                        }
                        #if os(macOS)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let ratio = min(max(location.x / max(geo.size.width, 1), 0), 1)
                            let targetBehind = (1.0 - ratio) * maxSeconds
                            player.seekToBehind(seconds: targetBehind)
                            model.showBanner()
                        }
                        .help("Klicken zum Springen im Puffer")
                        #endif
                    }
                    .frame(height: UI.s(12))

                    #if os(macOS)
                    HStack(spacing: UI.s(14)) {
                        timeshiftButton(icon: player.pausedSince != nil ? "play.fill" : "pause.fill",
                                        label: player.pausedSince != nil ? "Weiter" : "Pause") {
                            player.togglePause()
                            model.showBanner()
                        }
                        timeshiftButton(icon: "gobackward.30", label: "−30 s") {
                            player.jump(seconds: -30)
                            model.showBanner()
                        }
                        timeshiftButton(icon: "goforward.30", label: "+30 s") {
                            player.jump(seconds: 30)
                            model.showBanner()
                        }
                        timeshiftButton(icon: "dot.radiowaves.left.and.right", label: "Zum Live-Bild", accent: true) {
                            player.goLive()
                        }
                        Spacer()
                        timeshiftButton(icon: "info.circle", label: "Sendungsinfo") {
                            model.openInfoPanel()
                        }
                        timeshiftButton(icon: "list.bullet", label: "Senderliste") {
                            model.openChannelList()
                        }
                    }
                    #else
                    Text("\(UI.playPause): weiter/anhalten · \(UI.leftRight): spulen (10 s, 30 s, 1 m, 3 m, 5 m) · rechts bis zum Ende: Live")
                        .font(UI.font(24))
                        .foregroundStyle(UI.secondary)
                    #endif
                }
                .foregroundStyle(UI.text)
            }
        }
    }

    #if os(macOS)
    private func timeshiftButton(icon: String, label: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: UI.s(8)) {
                Image(systemName: icon)
                Text(label)
            }
            .font(UI.font(22, .semibold))
            .foregroundStyle(accent ? Color.black : UI.text)
            .padding(.horizontal, UI.s(20))
            .padding(.vertical, UI.s(10))
            .background(accent ? UI.accent : Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    #endif

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: Sendungsinfo (Klick in die Mitte)

struct InfoPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let selection: Int

    var body: some View {
        TopPanel(onTapOutside: { model.overlay = .none }) {
            VStack(alignment: .leading, spacing: UI.s(28)) {
                // Schalter oben
                let pills = model.availableInfoPills
                HStack(spacing: UI.s(16)) {
                    ForEach(0..<pills.count, id: \.self) { index in
                        pill(title(for: pills[index]), selected: selection == index)
                            #if os(macOS)
                            .contentShape(Capsule())
                            .onHover { hovering in
                                if hovering { model.overlay = .info(selection: index) }
                            }
                            .onTapGesture {
                                model.executeInfoPill(at: index)
                            }
                            #endif
                    }
                    #if os(macOS)
                    Spacer()
                    Button(action: { model.overlay = .none }) {
                        HStack(spacing: UI.s(8)) {
                            Image(systemName: "xmark")
                            Text("Schließen")
                        }
                        .font(UI.font(24, .semibold))
                        .foregroundStyle(UI.text)
                        .padding(.horizontal, UI.s(22))
                        .padding(.vertical, UI.s(12))
                        .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    #endif
                }

                // Sendungsinformationen (Jetzt & Danach)
                HStack(alignment: .top, spacing: UI.s(48)) {
                    // JETZT
                    VStack(alignment: .leading, spacing: UI.s(10)) {
                        HStack(spacing: UI.s(12)) {
                            ChannelLogoView(channelName: model.currentEntry?.group.displayName ?? "", height: UI.s(28), maxWidth: UI.s(90))
                            Text("\(player.isTimeshifted ? "ZEITVERSETZT" : "JETZT") · \(model.currentEntry?.number ?? 0) \(model.currentEntry?.group.displayName ?? "")")
                                .font(UI.font(24, .semibold))
                                .foregroundStyle(UI.secondary)
                        }

                        if let current = player.displayedProgram {
                            HStack(spacing: UI.s(16)) {
                                Text("\(Self.formatTime(current.startDate)) – \(Self.formatTime(current.endDate))")
                                    .font(UI.font(26, .bold))
                                    .foregroundStyle(UI.accent)
                                Text(current.title)
                                    .font(UI.font(38, .bold))
                                    .lineLimit(2)
                            }

                            TimelineView(.periodic(from: .now, by: 10)) { context in
                                let effectiveDate = context.date.addingTimeInterval(-player.currentBehind)
                                let progress = current.progress(at: effectiveDate)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.15))
                                        Capsule().fill(UI.accent)
                                            .frame(width: max(geo.size.width * progress, UI.s(6)))
                                    }
                                }
                                .frame(height: UI.s(6))
                            }

                            if let subtitle = current.subtitle {
                                Text(subtitle)
                                    .font(UI.font(24, .medium))
                                    .foregroundStyle(UI.secondary)
                                    .lineLimit(2)
                            }

                            if let desc = current.description {
                                Text(desc)
                                    .font(UI.font(22))
                                    .foregroundStyle(UI.secondary)
                                    .lineLimit(3)
                            }
                        } else {
                            Text(player.nowPlaying ?? "Keine Programminformation")
                                .font(UI.font(40, .bold))
                            Text("Ausführliche Programmdaten werden aus dem laufenden Stream geladen.")
                                .font(UI.font(24))
                                .foregroundStyle(UI.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // DANACH
                    if let next = player.displayedNextProgram {
                        VStack(alignment: .leading, spacing: UI.s(8)) {
                            Text("DANACH · Ab \(Self.formatTime(next.startDate))")
                                .font(UI.font(24, .semibold))
                                .foregroundStyle(UI.secondary)
                            Text(next.title)
                                .font(UI.font(32, .bold))
                                .lineLimit(2)
                            if let sub = next.subtitle ?? next.description {
                                Text(sub)
                                    .font(UI.font(22))
                                    .foregroundStyle(UI.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .frame(width: UI.s(420), alignment: .leading)
                        .padding(.leading, UI.s(24))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.12)).frame(width: UI.s(2))
                        }
                    }
                }

                // Stream-Qualität & Signal (VLC-Statistiken + Tuner)
                HStack(spacing: UI.s(20)) {
                    if !player.stats.resolutionLabel.isEmpty {
                        Label(player.stats.resolutionLabel, systemImage: "tv")
                    }
                    if !player.stats.bitrateLabel.isEmpty {
                        Label(player.stats.bitrateLabel, systemImage: "speedometer")
                    }
                    Label(player.stats.lossLabel,
                          systemImage: player.stats.lostPictures > 0 ? "exclamationmark.triangle" : "checkmark.shield")
                        .foregroundStyle(player.stats.lostPictures > 0 ? Color.orange : UI.secondary)

                    if let signal = player.stats.signalLabel {
                        Label(signal, systemImage: "antenna.radiowaves.left.and.right")
                    }
                    if let tuner = player.stats.tunerLabel {
                        Label(tuner, systemImage: "cpu")
                    }
                }
                .font(UI.font(20, .medium))
                .foregroundStyle(UI.secondary)
                .padding(.top, UI.s(4))

                Text("\(UI.leftRight): auswählen · \(UI.select): Aktion ausführen · \(UI.back) oder nach oben wischen: schließen")
                    .font(UI.font(22))
                    .foregroundStyle(UI.secondary)
            }
            .foregroundStyle(UI.text)
        }
    }

    private func title(for pill: AppModel.InfoPill) -> String {
        switch pill {
        case .audio: return "Ton: \(player.audioTrackName)"
        case .subtitle: return "Untertitel: \(player.subtitleName)"
        case .restartHLS: return "Von Anfang an"
        case .searchMediathek: return "In Mediathek suchen"
        case .settings: return "Einstellungen"
        }
    }

    private func pill(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(UI.font(26, .semibold))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.black : UI.text)
            .padding(.horizontal, UI.s(28))
            .padding(.vertical, UI.s(14))
            .background(selected ? UI.text : Color.white.opacity(0.14), in: Capsule())
            .scaleEffect(selected ? 1.08 : 1)
            .shadow(color: .black.opacity(selected ? 0.45 : 0), radius: 8, y: 4)
            .animation(.easeOut(duration: 0.15), value: selected)
    }

    static func formatTime(_ date: Date) -> String {
        UI.timeFormatter.string(from: date)
    }
}

// MARK: Senderliste (Zurück-Taste)

struct ChannelListOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let selectedID: String
    @Environment(\.windowSize) private var windowSize

    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var hoveredEntry: LineupEntry?

    private var isCompact: Bool {
        #if os(macOS)
        return windowSize.width < 760
        #else
        return false
        #endif
    }

    private let specialRowHeight: CGFloat = UI.s(58)
    private let sectionHeaderRecentHeight: CGFloat = UI.s(32)
    private let sectionHeaderAllHeight: CGFloat = UI.s(34)
    private let channelRowHeight: CGFloat = UI.s(74)
    private let settingsRowHeight: CGFloat = UI.s(68)
    private let itemSpacing: CGFloat = UI.s(6)

    private func itemMidY(for targetID: String) -> CGFloat {
        var y: CGFloat = UI.s(8) // oberes padding

        if targetID == "epgOverview" {
            return y + specialRowHeight / 2
        }
        y += specialRowHeight + itemSpacing

        if model.showsRadio {
            if targetID == "radio" {
                return y + specialRowHeight / 2
            }
            y += specialRowHeight + itemSpacing
        }

        if !model.recentEntries.isEmpty {
            y += sectionHeaderRecentHeight + itemSpacing
            for entry in model.recentEntries {
                let id = "recent-\(entry.number)"
                if id == targetID {
                    return y + channelRowHeight / 2
                }
                y += channelRowHeight + itemSpacing
            }
        }

        y += sectionHeaderAllHeight + itemSpacing
        for entry in model.lineup?.entries ?? [] {
            let id = "channel-\(entry.number)"
            if id == targetID {
                return y + channelRowHeight / 2
            }
            y += channelRowHeight + itemSpacing
        }

        if targetID == "settings" {
            return y + settingsRowHeight / 2
        }

        return y
    }

    private var totalEstimatedContentHeight: CGFloat {
        var h: CGFloat = UI.s(16)
        h += specialRowHeight + itemSpacing
        if model.showsRadio {
            h += specialRowHeight + itemSpacing
        }
        if !model.recentEntries.isEmpty {
            h += sectionHeaderRecentHeight + itemSpacing + CGFloat(model.recentEntries.count) * (channelRowHeight + itemSpacing)
        }
        let channelCount = CGFloat(model.lineup?.entries.count ?? 0)
        h += sectionHeaderAllHeight + itemSpacing + channelCount * (channelRowHeight + itemSpacing)
        h += settingsRowHeight
        return h
    }

    private var selectedChannelEntry: LineupEntry? {
        if let hoveredEntry {
            return hoveredEntry
        }
        if selectedID.hasPrefix("recent-"), let num = Int(selectedID.dropFirst("recent-".count)) {
            return model.recentEntries.first { $0.number == num } ?? model.lineup?.entry(number: num)
        }
        if selectedID.hasPrefix("channel-"), let num = Int(selectedID.dropFirst("channel-".count)) {
            return model.lineup?.entry(number: num)
        }
        return model.currentEntry
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: UI.s(14)) {
                GeometryReader { listGeo in
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: itemSpacing) {
                            specialRow("Programmübersicht", icon: "calendar.day.timeline.left", selected: selectedID == "epgOverview") {
                                model.openEPGOverview()
                            }
                            .frame(height: specialRowHeight)
                            .id("epgOverview")

                            if model.showsRadio {
                                specialRow("Radio", icon: "radio", selected: selectedID == "radio") {
                                    model.openRadioList()
                                }
                                .frame(height: specialRowHeight)
                                .id("radio")
                            }

                            if !model.recentEntries.isEmpty {
                                Text("ZULETZT GESEHEN")
                                    .font(UI.font(18, .bold))
                                    .foregroundStyle(UI.secondary.opacity(0.85))
                                    .padding(.top, UI.s(8))
                                    .padding(.bottom, UI.s(2))
                                    .padding(.horizontal, UI.s(20))
                                    .frame(height: sectionHeaderRecentHeight, alignment: .leading)
                                ForEach(model.recentEntries) { entry in
                                    row(entry, isRecentSection: true, selected: selectedID == "recent-\(entry.number)")
                                        .frame(height: channelRowHeight)
                                        .id("recent-\(entry.number)")
                                }
                            }

                            Text("ALLE SENDER")
                                .font(UI.font(18, .bold))
                                .foregroundStyle(UI.secondary.opacity(0.85))
                                .padding(.top, UI.s(10))
                                .padding(.bottom, UI.s(2))
                                .padding(.horizontal, UI.s(20))
                                .frame(height: sectionHeaderAllHeight, alignment: .leading)
                            ForEach(model.lineup?.entries ?? []) { entry in
                                row(entry, isRecentSection: false, selected: selectedID == "channel-\(entry.number)")
                                    .frame(height: channelRowHeight)
                                    .id("channel-\(entry.number)")
                            }

                            settingsRow(selected: selectedID == "settings")
                                .frame(height: settingsRowHeight)
                                .id("settings")
                        }
                        // Platz für die leicht vergrößerte Auswahl (sonst rechts abgeschnitten).
                        .padding(.horizontal, UI.s(20))
                        .padding(.vertical, UI.s(8))
                        .offset(y: scrollOffset)
                    }
                    .frame(width: listGeo.size.width, height: listGeo.size.height, alignment: .topLeading)
                    .clipped()
                    .onAppear {
                        viewportHeight = listGeo.size.height
                        updateScroll(animated: false, viewportHeight: listGeo.size.height)
                    }
                    .onChange(of: listGeo.size.height) { _, newHeight in
                        viewportHeight = newHeight
                        updateScroll(animated: false, viewportHeight: newHeight)
                    }
                }
                .onChange(of: selectedID) { _, _ in
                    updateScroll(animated: true, viewportHeight: viewportHeight)
                }

                Text("\(UI.select): umschalten · \(UI.back): schließen")
                    .font(UI.font(22))
                    .foregroundStyle(UI.secondary)
                    .padding(.horizontal, UI.s(20))
            }
            .padding(.vertical, isCompact ? 16 : UI.s(44))
            .padding(.horizontal, isCompact ? 12 : UI.s(20))
            .frame(width: isCompact ? windowSize.width : UI.s(760))
            .frame(maxHeight: .infinity)
            .background(Color(red: 0.055, green: 0.063, blue: 0.086).opacity(0.97))
            .overlay(alignment: .trailing) {
                if !isCompact {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
                }
            }
            .foregroundStyle(UI.text)

            if !isCompact {
                // Rechte Seite: EPG-Detailansicht für den fokussierten Sender
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.7)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.overlay = .none
                        }

                    if let entry = selectedChannelEntry {
                        epgDetailPane(for: entry)
                            .padding(UI.s(48))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        #if os(macOS)
        .onMacScrollWheel { _, dy in
            let minOffset = min(0, viewportHeight - totalEstimatedContentHeight)
            scrollOffset = max(minOffset, min(0, scrollOffset + dy))
        }
        #endif
    }

    private func updateScroll(animated: Bool, viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        let targetY = itemMidY(for: selectedID)
        let ideal = viewportHeight / 2 - targetY
        let maxOffset: CGFloat = 0
        let minOffset = min(0, viewportHeight - totalEstimatedContentHeight)
        let targetOffset = max(minOffset, min(maxOffset, ideal))

        if animated {
            withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.90)) {
                scrollOffset = targetOffset
            }
        } else {
            scrollOffset = targetOffset
        }
    }

    private func epgDetailPane(for entry: LineupEntry) -> some View {
        let isCurrent = entry.number == model.currentNumber
        let current = (isCurrent ? player.currentProgram : nil)
            ?? player.epgStore.currentProgram(forChannelNames: entry.group.epgNames)
        let next = player.epgStore.nextProgram(forChannelNames: entry.group.epgNames)

        return VStack(alignment: .leading, spacing: UI.s(24)) {
            // Sender-Kopfzeile
            HStack(spacing: UI.s(18)) {
                ChannelLogoView(channelName: entry.group.displayName, height: UI.s(48), maxWidth: UI.s(120))
                VStack(alignment: .leading, spacing: UI.s(4)) {
                    Text("\(entry.number) · \(entry.group.displayName)")
                        .font(UI.font(36, .heavy))
                        .foregroundStyle(UI.text)
                    HStack(spacing: UI.s(10)) {
                        if entry.group.hd != nil {
                            Badge(text: "HD")
                        } else {
                            Badge(text: "SD")
                        }
                        if isCurrent {
                            Badge(text: "LÄUFT")
                        }
                    }
                }
                Spacer()
            }

            Divider().background(Color.white.opacity(0.18))

            // JETZT
            VStack(alignment: .leading, spacing: UI.s(12)) {
                HStack {
                    Text("JETZT")
                        .font(UI.font(22, .bold))
                        .foregroundStyle(UI.accent)
                    if let current {
                        Text("· \(Self.formatTime(current.startDate)) – \(Self.formatTime(current.endDate))")
                            .font(UI.font(22, .medium))
                            .foregroundStyle(UI.secondary)
                    }
                }

                if let current {
                    Text(current.title)
                        .font(UI.font(34, .bold))
                        .foregroundStyle(UI.text)
                        .lineLimit(2)

                    TimelineView(.periodic(from: .now, by: 10)) { context in
                        let progress = current.progress(at: context.date)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(UI.accent)
                                    .frame(width: max(geo.size.width * progress, UI.s(6)))
                            }
                        }
                        .frame(height: UI.s(6))
                    }

                    if let subtitle = current.subtitle, !subtitle.isEmpty, subtitle != "(null)" {
                        Text(subtitle)
                            .font(UI.font(22, .semibold))
                            .foregroundStyle(UI.text.opacity(0.9))
                            .lineLimit(2)
                    }

                    if let desc = current.description, !desc.isEmpty, desc != "(null)" {
                        Text(desc)
                            .font(UI.font(20))
                            .foregroundStyle(UI.secondary)
                            .lineLimit(4)
                    }
                } else {
                    Text("Keine Programmdaten")
                        .font(UI.font(26, .semibold))
                        .foregroundStyle(UI.secondary)
                    Text("Ausführliche Programmdaten werden automatisch im Hintergrund aus dem Stream geladen.")
                        .font(UI.font(20))
                        .foregroundStyle(UI.secondary.opacity(0.8))
                }
            }
            .padding(UI.s(24))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: UI.s(20)))

            // DANACH
            if let next {
                VStack(alignment: .leading, spacing: UI.s(8)) {
                    Text("DANACH · Ab \(Self.formatTime(next.startDate))")
                        .font(UI.font(20, .bold))
                        .foregroundStyle(UI.secondary)
                    Text(next.title)
                        .font(UI.font(26, .bold))
                        .foregroundStyle(UI.text)
                        .lineLimit(2)
                    let sub = (next.subtitle ?? next.description)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let sub, !sub.isEmpty, sub != "(null)" {
                        Text(sub)
                            .font(UI.font(20))
                            .foregroundStyle(UI.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(UI.s(20))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: UI.s(16)))
            }

            #if os(macOS)
            HStack(spacing: UI.s(16)) {
                Button(action: {
                    model.overlay = .none
                    model.tune(to: entry.number)
                }) {
                    Label(isCurrent ? "Weiter schauen" : "Umschalten", systemImage: "play.fill")
                        .font(UI.font(22, .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, UI.s(24))
                        .padding(.vertical, UI.s(12))
                        .background(UI.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)

                if let hls = PublicHLSChannels.hlsURL(for: entry.group.key) {
                    Button(action: {
                        model.overlay = .none
                        model.startHLSReplay(url: hls, startDate: current?.startDate)
                    }) {
                        Label("Von Anfang an", systemImage: "clock.arrow.circlepath")
                            .font(UI.font(22, .semibold))
                            .foregroundStyle(UI.text)
                            .padding(.horizontal, UI.s(24))
                            .padding(.vertical, UI.s(12))
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                if let title = current?.title, !title.isEmpty {
                    Button(action: {
                        model.overlay = .none
                        model.searchMediathek(title: title, channel: entry.group.displayName)
                    }) {
                        Label("In Mediathek suchen", systemImage: "magnifyingglass")
                            .font(UI.font(22, .semibold))
                            .foregroundStyle(UI.text)
                            .padding(.horizontal, UI.s(24))
                            .padding(.vertical, UI.s(12))
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            #endif

            Spacer(minLength: 0)
        }
    }

    static func formatTime(_ date: Date) -> String {
        UI.timeFormatter.string(from: date)
    }

    private func specialRow(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: UI.s(16)) {
                if let icon {
                    Image(systemName: icon)
                        .font(UI.font(26, .semibold))
                        .foregroundStyle(selected ? Color.black : UI.accent)
                }
                Text(title)
                    .font(UI.font(28, .semibold))
                    .foregroundStyle(selected ? Color.black : UI.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(UI.font(20, .semibold))
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : UI.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, UI.s(20))
            .padding(.vertical, UI.s(11))
            .background(selected ? UI.text : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: UI.s(14)))
            .overlay(RoundedRectangle(cornerRadius: UI.s(14)).stroke(Color.white.opacity(selected ? 0 : 0.2), lineWidth: UI.s(1.5)))
            .focusLift(selected)
        }
        .buttonStyle(ListRowButtonStyle())
        // Die Fernbedienung steuert die Liste über AppModel.handle; auf dem Apple TV dürfen die
        // Knöpfe den Fokus nicht übernehmen (sonst wirken Klick und Pfeile auf eine andere Zeile).
        .focusable(false)
    }

    private func settingsRow(selected: Bool) -> some View {
        let ink: Color = selected ? .black : UI.text
        let quiet: Color = selected ? Color(white: 0.3) : UI.secondary
        let bg = selected ? UI.text : Color.white.opacity(0.08)
        let strokeColor = selected ? Color.clear : Color.white.opacity(0.18)

        return Button(action: {
            model.overlay = .none
            model.showSettings = true
        }) {
            HStack(spacing: UI.s(16)) {
                Image(systemName: "gearshape.fill")
                    .font(UI.font(26, .semibold))
                    .foregroundStyle(selected ? Color.black : UI.accent)
                    .frame(width: UI.s(48), alignment: .center)
                VStack(alignment: .leading, spacing: UI.s(2)) {
                    Text("Einstellungen")
                        .font(UI.font(28, .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text("Sender sortieren, FRITZ!Box, Bild & Ton")
                        .font(UI.font(20))
                        .foregroundStyle(quiet)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(UI.font(20, .semibold))
                    .foregroundStyle(quiet)
            }
            .padding(.horizontal, UI.s(20))
            .padding(.vertical, UI.s(12))
            .background(bg, in: RoundedRectangle(cornerRadius: UI.s(14)))
            .overlay(
                RoundedRectangle(cornerRadius: UI.s(14))
                    .stroke(strokeColor, lineWidth: UI.s(1.5))
            )
            .contentShape(Rectangle())
            .focusLift(selected)
        }
        .buttonStyle(ListRowButtonStyle())
        // Die Fernbedienung steuert die Liste über AppModel.handle; auf dem Apple TV dürfen die
        // Knöpfe den Fokus nicht übernehmen (sonst wirken Klick und Pfeile auf eine andere Zeile).
        .focusable(false)
    }

    private func row(_ entry: LineupEntry, isRecentSection: Bool, selected: Bool) -> some View {
        let isCurrent = entry.number == model.currentNumber
        let ink: Color = selected ? .black : UI.text
        let quiet: Color = selected ? Color(white: 0.3) : UI.secondary

        let current = (isCurrent ? player.currentProgram : nil)
            ?? player.epgStore.currentProgram(forChannelNames: entry.group.epgNames)
        let isDead = entry.group.areAllVariantsDead(deadIDs: model.settings.deadChannelIDs)

        return Button(action: {
            model.overlay = .none
            model.tune(to: entry.number)
        }) {
            HStack(spacing: UI.s(16)) {
                Text("\(entry.number)")
                    .font(UI.font(28, .bold))
                    .foregroundStyle(quiet)
                    .frame(width: UI.s(52), alignment: .leading)
                ChannelLogoView(channelName: entry.group.displayName, height: UI.s(30), maxWidth: UI.s(68))
                VStack(alignment: .leading, spacing: UI.s(3)) {
                    HStack(spacing: UI.s(8)) {
                        Text(entry.group.displayName + (entry.isNew ? " · neu" : ""))
                            .font(UI.font(26, .semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        if entry.group.hd != nil {
                            Text("HD")
                                .font(UI.font(15, .bold))
                                .foregroundStyle(selected ? Color.black.opacity(0.8) : UI.accent)
                                .padding(.horizontal, UI.s(6))
                                .padding(.vertical, UI.s(2))
                                .background(selected ? Color.black.opacity(0.12) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: UI.s(4)))
                        }
                    }
                    if let current {
                        Text("\(Self.formatTime(current.startDate)) – \(Self.formatTime(current.endDate)) · \(current.title)")
                            .font(UI.font(20))
                            .foregroundStyle(quiet)
                            .lineLimit(1)
                    } else {
                        Text(entry.group.hd != nil && entry.group.sd != nil ? "HD + SD" : (entry.group.hd != nil ? "HD" : "SD"))
                            .font(UI.font(20))
                            .foregroundStyle(quiet)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isRecentSection {
                    Badge(text: "ZULETZT", dark: selected)
                } else if isCurrent {
                    Badge(text: "LÄUFT", dark: selected)
                } else if isDead {
                    Badge(text: "KEIN SIGNAL", dark: selected)
                }
            }
            .padding(.horizontal, UI.s(20))
            .padding(.vertical, UI.s(9))
            .background(selected ? UI.text : (isCurrent ? Color.white.opacity(0.08) : Color.clear),
                        in: RoundedRectangle(cornerRadius: UI.s(14)))
            .contentShape(Rectangle())
            .focusLift(selected)
        }
        .buttonStyle(ListRowButtonStyle())
        // Die Fernbedienung steuert die Liste über AppModel.handle; auf dem Apple TV dürfen die
        // Knöpfe den Fokus nicht übernehmen (sonst wirken Klick und Pfeile auf eine andere Zeile).
        .focusable(false)
        #if os(macOS)
        .onHover { hovering in
            if hovering {
                hoveredEntry = entry
            } else if hoveredEntry?.number == entry.number {
                hoveredEntry = nil
            }
        }
        #endif
    }
}

// MARK: Direktwahl

struct DirectEntryOverlay: View {
    @ObservedObject var model: AppModel
    let digits: String
    let key: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                #if os(macOS)
                .onTapGesture { model.overlay = .none }
                #endif
            VStack(spacing: UI.s(20)) {
                Text("Sender-Direktwahl").font(UI.font(28, .semibold)).foregroundStyle(UI.secondary)
                Text(digits.isEmpty ? "–" : digits).font(UI.font(96, .heavy))
                Text(previewText).font(UI.font(28)).foregroundStyle(UI.secondary).lineLimit(1)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(UI.s(160)), spacing: UI.s(16)), count: 3),
                          spacing: UI.s(16)) {
                    ForEach(0..<AppModel.keypad.count, id: \.self) { index in
                        let label = AppModel.keypad[index]
                        Text(label)
                            .font(UI.font(label.count > 2 ? 26 : 44, .semibold))
                            .frame(width: UI.s(160), height: UI.s(96))
                            .foregroundStyle(index == key ? Color.black : UI.text)
                            .background(index == key ? UI.text : Color.white.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: UI.s(16)))
                            .focusLift(index == key, scale: 1.08)
                            #if os(macOS)
                            .contentShape(RoundedRectangle(cornerRadius: UI.s(16)))
                            .onTapGesture { model.tapDirectKey(index) }
                            #endif
                    }
                }
                #if os(macOS)
                Text("Ziffern tippen oder anklicken · Return: OK · Esc: abbrechen").font(UI.font(24)).foregroundStyle(UI.secondary)
                #endif
            }
            .foregroundStyle(UI.text)
            .padding(UI.s(48))
            .background { PanelBackground(cornerRadius: UI.s(32)) }
        }
    }

    private var previewText: String {
        guard !digits.isEmpty else { return " " }
        guard let entry = model.directPreview(digits) else { return "Kein Sender auf diesem Platz" }
        return entry.group.displayName
    }
}

// MARK: Senderleiste unten (Wischen nach oben)

/// Senderleiste zum Stöbern während der Wiedergabe (Apple: „content footer“): Logo, laufende
/// Sendung und Fortschritt; der laufende Sender ist markiert. Links/Rechts wählt, Klick schaltet um.
struct ChannelFooter: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let index: Int

    private let cardWidth: CGFloat = UI.s(330)
    private let spacing: CGFloat = UI.s(28)

    var body: some View {
        let entries = model.lineup?.entries ?? []
        VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .bottom) {
                // Dezente Abdunklung, damit Schrift und Karten vom Bild abgesetzt sind.
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: UI.s(420))
                    .ignoresSafeArea(edges: .bottom)
                VStack(alignment: .leading, spacing: UI.s(16)) {
                    Text("\(UI.leftRight): Sender wählen · \(UI.select): umschalten · nach unten wischen: schließen")
                        .font(UI.font(23))
                        .foregroundStyle(UI.secondary)
                    GeometryReader { geo in
                        let center = geo.size.width / 2 - cardWidth / 2
                        ZStack(alignment: .topLeading) {
                            ForEach(max(0, index - 4)..<min(entries.count, index + 5), id: \.self) { i in
                                card(entries[i], selected: i == index)
                                    .offset(x: center + CGFloat(i - index) * (cardWidth + spacing))
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    }
                    .frame(height: UI.s(210))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func card(_ entry: LineupEntry, selected: Bool) -> some View {
        let isCurrent = entry.number == model.currentNumber
        let program = (isCurrent ? player.currentProgram : nil)
            ?? player.epgStore.currentProgram(forChannelNames: entry.group.epgNames)
        return VStack(alignment: .leading, spacing: UI.s(10)) {
            HStack(spacing: UI.s(12)) {
                ChannelLogoView(channelName: entry.group.displayName, height: UI.s(40), maxWidth: UI.s(90))
                Text("\(entry.number)")
                    .font(UI.font(26, .bold))
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : UI.secondary)
                Spacer(minLength: 0)
                if isCurrent {
                    Text("LÄUFT")
                        .font(UI.font(23, .heavy))
                        .foregroundStyle(selected ? Color.white : Color.black)
                        .padding(.horizontal, UI.s(8))
                        .background(selected ? Color.black.opacity(0.7) : UI.accent, in: Capsule())
                }
            }
            Text(entry.group.displayName)
                .font(UI.font(26, .semibold))
                .foregroundStyle(selected ? Color.black : UI.text)
                .lineLimit(1)
            Text(program?.title ?? "Keine Programmdaten")
                .font(UI.font(23))
                .foregroundStyle(selected ? Color.black.opacity(0.75) : UI.secondary)
                .lineLimit(1)
            if let program {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill((selected ? Color.black : Color.white).opacity(0.18))
                        Capsule().fill(isCurrent ? UI.accent : (selected ? Color.black.opacity(0.6) : Color.white.opacity(0.6)))
                            .frame(width: max(geo.size.width * program.progress(at: Date()), UI.s(6)))
                    }
                }
                .frame(height: UI.s(6))
            }
        }
        .padding(UI.s(20))
        .frame(width: cardWidth, height: UI.s(190), alignment: .topLeading)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: UI.s(20)).fill(UI.text)
            } else {
                PanelBackground(cornerRadius: UI.s(20))
            }
        }
        .focusLift(selected, scale: 1.08)
        #if os(macOS)
        .contentShape(RoundedRectangle(cornerRadius: UI.s(20)))
        .onTapGesture {
            model.overlay = .none
            model.tune(to: entry.number)
        }
        #endif
    }
}
