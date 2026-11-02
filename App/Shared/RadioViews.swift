import SwiftUI
import FritzTVKit

// MARK: Anzeige während Radio läuft

/// Anzeige anstelle des Bildes. Sie wandert langsam über den Bildschirm, damit auf OLED-Fernsehern
/// nichts einbrennt, falls der Bildschirmschoner abgeschaltet ist.
struct RadioCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let group: ChannelGroup

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let slot = Int(context.date.timeIntervalSince1970 / 30)
            card
                .offset(x: UI.s(220) * sin(Double(slot) * 1.3), y: UI.s(140) * cos(Double(slot) * 0.7))
                .animation(.easeInOut(duration: 12), value: slot)
        }
    }

    /// Während des Umschaltens gehört der gemeldete Titel noch zum vorigen Sender.
    private var reportedTitle: String? {
        guard group.variants.contains(where: { $0.id == player.channel?.id }),
              let title = player.nowPlaying, !title.isEmpty,
              !EPGProgram.isPlaceholderTitle(title) else { return nil }
        return title
    }

    private var card: some View {
        VStack(spacing: UI.s(20)) {
            ChannelLogoView(channelName: group.displayName, height: UI.s(150), maxWidth: UI.s(340),
                            urls: ChannelLogo.radioCandidateURLs(for: group.displayName), fallbackIcon: "radio")
            Text(group.displayName)
                .font(UI.font(60, .heavy))
                .lineLimit(1)
            if model.radioPaused {
                Text("Angehalten")
                    .font(UI.font(32))
                    .foregroundStyle(UI.secondary)
            } else {
                RadioProgramInfo(store: player.epgStore, station: group, fallbackTitle: reportedTitle)
            }
            Text("\(UI.upDown): anderer Radiosender · \(UI.back): Radioliste")
                .font(UI.font(22))
                .foregroundStyle(UI.secondary)
                .padding(.top, UI.s(16))
        }
        .foregroundStyle(UI.text)
        .padding(UI.s(48))
    }
}

/// Laufende und folgende Sendung aus den Programmdaten des Signals. Sender ohne echte Programmdaten
/// zeigen nur `fallbackTitle` bzw. nichts.
private struct RadioProgramInfo: View {
    let store: EPGStore
    let station: ChannelGroup
    var fallbackTitle: String? = nil

    private func real(_ program: EPGProgram?) -> EPGProgram? {
        guard let program, !EPGProgram.isPlaceholderTitle(program.title) else { return nil }
        return program
    }

    var body: some View {
        let current = real(store.currentProgram(forChannelNames: station.epgNames))
        let next = real(store.nextProgram(forChannelNames: station.epgNames))
        VStack(spacing: UI.s(8)) {
            if let current {
                Text(current.title)
                    .font(UI.font(34, .bold))
                    .foregroundStyle(UI.text)
                Text("\(UI.timeFormatter.string(from: current.startDate)) – \(UI.timeFormatter.string(from: current.endDate))")
                    .font(UI.font(24))
                    .foregroundStyle(UI.secondary)
                if let subtitle = current.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(UI.font(26))
                        .foregroundStyle(UI.secondary)
                }
            } else if let fallbackTitle {
                Text(fallbackTitle)
                    .font(UI.font(32))
                    .foregroundStyle(UI.secondary)
            }
            if let next {
                Text("Ab \(UI.timeFormatter.string(from: next.startDate)): \(next.title)")
                    .font(UI.font(24))
                    .foregroundStyle(UI.secondary)
                    .padding(.top, UI.s(8))
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
}

// MARK: Radioliste

/// Eigene Liste statt eines Abschnitts in der Senderliste: So bleibt die Senderliste bis auf eine
/// Zeile unverändert, auch wenn die Box viele Radiosender meldet.
struct RadioListOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let selectedID: String
    @Environment(\.windowSize) private var windowSize

    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private let rowHeight: CGFloat = UI.s(62)
    private let headerHeight: CGFloat = UI.s(38)
    private let itemSpacing: CGFloat = UI.s(6)

    private var isCompact: Bool {
        #if os(macOS)
        return windowSize.width < 760
        #else
        return false
        #endif
    }

    private enum ListLine: Identifiable {
        case header(String)
        case item(RadioListItem)

        var id: String {
            switch self {
            case .header(let title): return "header-\(title)"
            case .item(let item): return item.id
            }
        }
    }

    private var lines: [ListLine] {
        var result: [ListLine] = []
        var section: String?
        for item in model.radioListItems {
            let wanted: String?
            switch item {
            case .backToTV: wanted = nil
            case .recent: wanted = "ZULETZT GEHÖRT"
            case .station: wanted = "ALLE RADIOSENDER (\(model.radioStations.all.count))"
            }
            if let wanted, wanted != section {
                result.append(.header(wanted))
                section = wanted
            }
            result.append(.item(item))
        }
        return result
    }

    private func height(of line: ListLine) -> CGFloat {
        if case .header = line { return headerHeight }
        return rowHeight
    }

    private func midY(of targetID: String, in lines: [ListLine]) -> CGFloat {
        var y = UI.s(8)
        for line in lines {
            if line.id == targetID { return y + height(of: line) / 2 }
            y += height(of: line) + itemSpacing
        }
        return y
    }

    private func contentHeight(of lines: [ListLine]) -> CGFloat {
        lines.reduce(UI.s(16)) { $0 + height(of: $1) + itemSpacing }
    }

    private var selectedStation: ChannelGroup? {
        for item in model.radioListItems where item.id == selectedID {
            switch item {
            case .recent(let group), .station(let group): return group
            case .backToTV: return nil
            }
        }
        return nil
    }

    var body: some View {
        let lines = lines
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: UI.s(14)) {
                GeometryReader { listGeo in
                    VStack(alignment: .leading, spacing: itemSpacing) {
                        ForEach(lines) { line in
                            switch line {
                            case .header(let title):
                                Text(title)
                                    .font(UI.font(18, .bold))
                                    .foregroundStyle(UI.secondary.opacity(0.85))
                                    .padding(.horizontal, UI.s(20))
                                    .frame(height: headerHeight, alignment: .bottomLeading)
                            case .item(let item):
                                itemRow(item)
                                    .frame(height: rowHeight)
                            }
                        }
                    }
                    // Platz für die leicht vergrößerte Auswahl (sonst rechts abgeschnitten).
                    .padding(.horizontal, UI.s(20))
                    .padding(.vertical, UI.s(8))
                    .offset(y: scrollOffset)
                    .frame(width: listGeo.size.width, height: listGeo.size.height, alignment: .topLeading)
                    .clipped()
                    .onAppear {
                        viewportHeight = listGeo.size.height
                        updateScroll(lines: lines, animated: false)
                    }
                    .onChange(of: listGeo.size.height) { _, newHeight in
                        viewportHeight = newHeight
                        updateScroll(lines: lines, animated: false)
                    }
                }
                .onChange(of: selectedID) { _, _ in
                    updateScroll(lines: lines, animated: true)
                }

                Text("\(UI.select): abspielen · \(UI.back): schließen")
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
                ZStack {
                    Color.black.opacity(0.7)
                        .contentShape(Rectangle())
                        .onTapGesture { model.overlay = .none }
                    if let station = selectedStation {
                        stationPane(station)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        #if os(macOS)
        .onMacScrollWheel { _, dy in
            let minOffset = min(0, viewportHeight - contentHeight(of: lines))
            scrollOffset = max(minOffset, min(0, scrollOffset + dy))
        }
        #endif
    }

    private func updateScroll(lines: [ListLine], animated: Bool) {
        guard viewportHeight > 0 else { return }
        let ideal = viewportHeight / 2 - midY(of: selectedID, in: lines)
        let target = max(min(0, viewportHeight - contentHeight(of: lines)), min(0, ideal))
        if animated {
            withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.90)) { scrollOffset = target }
        } else {
            scrollOffset = target
        }
    }

    private func itemRow(_ item: RadioListItem) -> some View {
        let title: String
        let icon: String
        let isCurrent: Bool
        switch item {
        case .backToTV:
            title = "Zurück zum Fernsehen"
            icon = "tv"
            isCurrent = false
        case .recent(let group), .station(let group):
            title = group.displayName
            isCurrent = group == model.currentRadio
            icon = isCurrent ? "speaker.wave.2.fill" : "radio"
        }
        return Button {
            model.activateRadioListItem(item)
        } label: {
            RadioRow(title: title, icon: icon, isCurrent: isCurrent, selected: item.id == selectedID)
                .equatable()
        }
        .buttonStyle(ListRowButtonStyle())
        // Die Fernbedienung steuert die Liste über AppModel.handle; auf dem Apple TV dürfen die
        // Knöpfe den Fokus nicht übernehmen (sonst wirken Klick und Pfeile auf eine andere Zeile).
        .focusable(false)
    }

    private func stationPane(_ station: ChannelGroup) -> some View {
        let isCurrent = station == model.currentRadio
        return VStack(spacing: UI.s(20)) {
            ChannelLogoView(channelName: station.displayName, height: UI.s(150), maxWidth: UI.s(340),
                            urls: ChannelLogo.radioCandidateURLs(for: station.displayName), fallbackIcon: "radio")
            Text(station.displayName)
                .font(UI.font(48, .heavy))
                .foregroundStyle(UI.text)
                .multilineTextAlignment(.center)
            if isCurrent {
                Badge(text: "LÄUFT")
            }
            RadioProgramInfo(store: player.epgStore, station: station)
        }
        .padding(UI.s(48))
    }
}

/// Zeile der Radioliste. `Equatable`, damit beim schnellen Blättern durch sehr viele Sender nur
/// die zwei Zeilen neu gezeichnet werden, deren Auswahl sich ändert.
private struct RadioRow: View, Equatable {
    let title: String
    let icon: String
    let isCurrent: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: UI.s(16)) {
            Image(systemName: icon)
                .font(UI.font(24, .semibold))
                .foregroundStyle(selected ? Color.black : UI.accent)
                .frame(width: UI.s(48))
            Text(title)
                .font(UI.font(26, .semibold))
                .foregroundStyle(selected ? Color.black : UI.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isCurrent {
                Badge(text: "LÄUFT", dark: selected)
            }
        }
        .padding(.horizontal, UI.s(20))
        .frame(maxHeight: .infinity)
        .background(selected ? UI.text : (isCurrent ? Color.white.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: UI.s(14)))
        .contentShape(Rectangle())
        .focusLift(selected)
    }
}
