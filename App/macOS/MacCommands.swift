import SwiftUI
import FritzTVKit

/// Menüs „Wiedergabe“ und „Sender“: Jeder Befehl ist auffindbar und hat, wo sinnvoll, einen
/// Kurzbefehl. Die Belegung folgt FritzRadio (⌘↑/⌘↓ Lautstärke, ⌘←/⌘→ Sender).
/// Pfeiltasten ohne ⌘ (Sender, Spulen) und die Leertaste wertet `RemoteInputModifier` aus.
struct MacCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController

    /// Befehle für das Live-Bild: gesperrt, solange Einstellungen, Suchergebnisse oder eine
    /// Mediathek-Wiedergabe offen sind (⌘←/⌘→ gehören dort z. B. dem Textfeld).
    private var liveCommandsEnabled: Bool {
        model.loadState == .ready && !model.showSettings && model.searchResultDialog == nil
            && model.activeHLSReplay == nil && model.activeMediathekURL == nil
    }

    var body: some Commands {
        CommandMenu("Wiedergabe") {
            Button(player.pausedSince != nil ? "Weiter" : "Anhalten") {
                player.togglePause()
                model.showBanner()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!liveCommandsEnabled)

            Button("Zum Live-Bild") { player.goLive() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!liveCommandsEnabled || !player.isTimeshifted)

            Button("10 Sekunden zurück") {
                player.jump(seconds: -10)
                model.showBanner()
            }
            .disabled(!liveCommandsEnabled)

            Button("10 Sekunden vor") {
                player.jump(seconds: 10)
                model.showBanner()
            }
            .disabled(!liveCommandsEnabled || !player.isTimeshifted)

            Button("Sendung von Anfang an") {
                if let entry = model.currentEntry, let hls = PublicHLSChannels.hlsURL(for: entry.group.key) {
                    model.startHLSReplay(url: hls, startDate: player.displayedProgram?.startDate)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            .disabled(!liveCommandsEnabled || model.currentEntry.flatMap { PublicHLSChannels.hlsURL(for: $0.group.key) } == nil)

            Divider()

            Button("Lauter") { model.changeVolume(by: 10) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Leiser") { model.changeVolume(by: -10) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Toggle("Ton aus", isOn: $model.isMuted)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            let audio = player.audioTrackOptions
            Picker("Tonspur", selection: Binding(get: { player.currentAudioTrackID },
                                                 set: { player.selectAudioTrack($0) })) {
                ForEach(audio) { Text($0.name).tag($0.id) }
            }
            .disabled(audio.count < 2)

            let subtitles = player.subtitleOptions
            Picker("Untertitel", selection: Binding(get: { player.currentSubtitleID },
                                                    set: { player.selectSubtitle($0) })) {
                ForEach(subtitles) { Text($0.name).tag($0.id) }
            }
            .disabled(subtitles.count < 2)
        }

        CommandMenu("Sender") {
            Button("Nächster Sender") { model.stepChannel(+1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!liveCommandsEnabled)
            Button("Voriger Sender") { model.stepChannel(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!liveCommandsEnabled)

            Divider()

            Button("Senderliste") {
                if case .channelList = model.overlay {
                    model.overlay = .none
                } else {
                    model.openChannelList()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(!liveCommandsEnabled)

            Button("Sendungsinfo") {
                if case .info = model.overlay {
                    model.overlay = .none
                } else {
                    model.openInfoPanel()
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!liveCommandsEnabled)

            Button("Programmübersicht") {
                if model.showEPGOverview {
                    model.closeEPGOverview()
                } else {
                    model.openEPGOverview()
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!liveCommandsEnabled)

            Divider()

            Button("In der Mediathek suchen") {
                if let title = player.displayedProgram?.title ?? player.nowPlaying, !title.isEmpty {
                    model.searchMediathek(title: title, channel: model.currentEntry?.group.displayName)
                }
            }
            .disabled(!liveCommandsEnabled || (player.displayedProgram?.title ?? player.nowPlaying ?? "").isEmpty)
        }
    }
}
