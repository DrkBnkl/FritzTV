import SwiftUI
import FritzTVKit

// MARK: Bausteine

private struct Badge: View {
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack {
            Spacer()
            content
                .padding(.horizontal, UI.s(48))
                .padding(.vertical, UI.s(36))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(UI.panel, in: RoundedRectangle(cornerRadius: UI.s(32)))
                .padding(.horizontal, UI.s(96))
                .padding(.bottom, UI.s(60))
        }
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
        .background(UI.panel, in: RoundedRectangle(cornerRadius: UI.s(28)))
    }
}

// MARK: Infoleiste nach dem Umschalten

struct InfoBanner: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController

    var body: some View {
        if let entry = model.currentEntry {
            BottomPanel {
                HStack(spacing: UI.s(48)) {
                    VStack(spacing: UI.s(4)) {
                        Text("\(entry.number)").font(UI.font(96, .heavy))
                        Text(entry.group.displayName).font(UI.font(30, .semibold)).lineLimit(1)
                    }
                    .frame(width: UI.s(220))

                    VStack(alignment: .leading, spacing: UI.s(10)) {
                        Text("JETZT").font(UI.font(24, .semibold)).foregroundStyle(UI.secondary)
                        Text(player.nowPlaying ?? "Keine Programminformation")
                            .font(UI.font(44, .bold))
                            .lineLimit(2)
                    }

                    Spacer(minLength: UI.s(24))

                    VStack(alignment: .trailing, spacing: UI.s(16)) {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(context.date, format: .dateTime.hour().minute()).font(UI.font(44, .semibold))
                        }
                        Badge(text: player.channel?.isHD == false ? "SD" : "HD")
                    }
                }
                .foregroundStyle(UI.text)
            }
        }
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
                        if let title = player.nowPlaying {
                            Text("· \(title)").font(UI.font(32)).lineLimit(1)
                        }
                        Spacer()
                        Text(player.pausedSince != nil ? "Angehalten · \(Self.format(behind)) hinter Live"
                                                       : "\(Self.format(behind)) hinter Live")
                            .font(UI.font(32, .bold))
                            .foregroundStyle(UI.accent)
                    }
                    GeometryReader { geo in
                        let share = min(behind / 3600, 1)
                        ZStack(alignment: .trailing) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(Color.white.opacity(0.5))
                                .frame(width: max(geo.size.width * share, UI.s(8)))
                        }
                    }
                    .frame(height: UI.s(8))
                    Text("\(UI.playPause): weiter/anhalten · \(UI.leftRight): 10 s · rechts bis zum Ende: Live")
                        .font(UI.font(24))
                        .foregroundStyle(UI.secondary)
                }
                .foregroundStyle(UI.text)
            }
        }
    }

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
        BottomPanel {
            VStack(alignment: .leading, spacing: UI.s(32)) {
                HStack(spacing: UI.s(24)) {
                    pill("Ton: \(player.audioTrackName)", selected: selection == 0)
                    pill("Untertitel: \(player.subtitleName)", selected: selection == 1)
                    Spacer()
                    pill("Einstellungen", selected: selection == 2)
                }
                VStack(alignment: .leading, spacing: UI.s(12)) {
                    Text("JETZT · \(model.currentEntry?.number ?? 0) \(model.currentEntry?.group.displayName ?? "")")
                        .font(UI.font(24, .semibold))
                        .foregroundStyle(UI.secondary)
                    Text(player.nowPlaying ?? "Keine Programminformation")
                        .font(UI.font(44, .bold))
                    Text("Beschreibung und „Danach“ folgen mit dem eigenen EPG-Leser.")
                        .font(UI.font(26))
                        .foregroundStyle(UI.secondary)
                }
                Text("\(UI.leftRight): auswählen · \(UI.select): umschalten · \(UI.back): schließen")
                    .font(UI.font(24))
                    .foregroundStyle(UI.secondary)
            }
            .foregroundStyle(UI.text)
        }
    }

    private func pill(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(UI.font(28, .semibold))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.black : UI.text)
            .padding(.horizontal, UI.s(32))
            .padding(.vertical, UI.s(16))
            .background(selected ? UI.text : Color.white.opacity(0.14), in: Capsule())
    }
}

// MARK: Senderliste (Zurück-Taste)

struct ChannelListOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let selection: Int
    let moving: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: UI.s(16)) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sender").font(UI.font(44, .heavy))
                    Spacer()
                    Text("\(model.lineup?.entries.count ?? 0) Plätze · \(model.lineup?.hiddenGroups.count ?? 0) ausgeblendet")
                        .font(UI.font(24))
                        .foregroundStyle(UI.secondary)
                }
                .padding(.horizontal, UI.s(24))

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: UI.s(8)) {
                            specialRow("Mediathek · Spielfilme", selected: selection == -1).id(-1)
                            specialRow("Platz eingeben (Direktwahl)", selected: selection == 0).id(0)
                            ForEach(model.lineup?.entries ?? []) { entry in
                                row(entry).id(entry.number)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, new in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }

                Text(moving ? "\(UI.upDown): verschieben · \(UI.select): fertig"
                            : "\(UI.select): umschalten · \(UI.playPause): verschieben · \(UI.back): schließen")
                    .font(UI.font(24))
                    .foregroundStyle(UI.secondary)
                    .padding(.horizontal, UI.s(24))
            }
            .padding(.vertical, UI.s(56))
            .padding(.horizontal, UI.s(40))
            .frame(width: UI.s(820))
            .frame(maxHeight: .infinity)
            .background(Color(red: 0.055, green: 0.063, blue: 0.086).opacity(0.95))
            .foregroundStyle(UI.text)

            Spacer()
        }
        .ignoresSafeArea()
    }

    private func specialRow(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(UI.font(28, .semibold))
            .foregroundStyle(selected ? Color.black : UI.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, UI.s(24))
            .padding(.vertical, UI.s(14))
            .background(selected ? UI.text : Color.clear, in: RoundedRectangle(cornerRadius: UI.s(16)))
            .overlay(RoundedRectangle(cornerRadius: UI.s(16)).stroke(Color.white.opacity(selected ? 0 : 0.25), lineWidth: UI.s(2)))
    }

    private func row(_ entry: LineupEntry) -> some View {
        let selected = selection == entry.number
        let isCurrent = entry.number == model.currentNumber
        let isPrevious = AppModel.key(entry) == model.previousKey
        let ink: Color = selected ? .black : UI.text
        let quiet: Color = selected ? Color(white: 0.3) : UI.secondary

        let detail: String
        if isCurrent, let title = player.nowPlaying {
            detail = title
        } else if entry.group.hd != nil && entry.group.sd != nil {
            detail = "HD + SD"
        } else {
            detail = entry.group.hd != nil ? "HD" : "SD"
        }

        return HStack(spacing: UI.s(24)) {
            Text("\(entry.number)")
                .font(UI.font(32, .bold))
                .foregroundStyle(quiet)
                .frame(width: UI.s(72), alignment: .leading)
            VStack(alignment: .leading, spacing: UI.s(4)) {
                Text(entry.group.displayName + (entry.isNew ? " · neu" : ""))
                    .font(UI.font(32, .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(detail).font(UI.font(24)).foregroundStyle(quiet).lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected && moving {
                Badge(text: "↕ VERSCHIEBEN", dark: true)
            } else if isCurrent {
                Badge(text: "LÄUFT", dark: selected)
            } else if isPrevious {
                Badge(text: "ZULETZT", dark: selected)
            }
        }
        .padding(.horizontal, UI.s(24))
        .padding(.vertical, UI.s(14))
        .background(selected ? UI.text : (isCurrent ? Color.white.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: UI.s(16)))
    }
}

// MARK: Direktwahl

struct DirectEntryOverlay: View {
    @ObservedObject var model: AppModel
    let digits: String
    let key: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: UI.s(20)) {
                Text("Platz eingeben").font(UI.font(28, .semibold)).foregroundStyle(UI.secondary)
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
                    }
                }
                #if os(macOS)
                Text("Ziffern tippen · Return: OK · Esc: abbrechen").font(UI.font(24)).foregroundStyle(UI.secondary)
                #endif
            }
            .foregroundStyle(UI.text)
            .padding(UI.s(48))
            .background(UI.panel, in: RoundedRectangle(cornerRadius: UI.s(32)))
        }
    }

    private var previewText: String {
        guard !digits.isEmpty else { return " " }
        guard let entry = model.directPreview(digits) else { return "Kein Sender auf diesem Platz" }
        return entry.group.displayName
    }
}
