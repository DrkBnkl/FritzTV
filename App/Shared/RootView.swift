import SwiftUI
import FritzTVKit

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: player.mediaPlayer)
                .ignoresSafeArea()
            // Timeshift: Mitschnitt-Wiedergabe liegt über dem stumm weiterlaufenden Live-Bild.
            PlayerSurface(player: player.replayPlayer)
                .ignoresSafeArea()
                .opacity(player.isReplaying ? 1 : 0)
                .allowsHitTesting(false)
            OverlayLayer(model: model, player: player)
        }
        .modifier(RemoteInputModifier(model: model))
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            model.handleDeepLink(url: url)
        }
        .sheet(isPresented: $model.showSettings, onDismiss: { model.applySettings() }) {
            SettingsView(model: model, settings: model.settings)
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $model.showMediathek, onDismiss: { model.mediathekClosed() }) {
            MediathekView(settings: model.settings)
        }
        .fullScreenCover(isPresented: $model.showEPGOverview) {
            EPGOverviewView(model: model, player: player, scanner: model.epgScanner)
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.activeHLSReplay != nil },
            set: { if !$0 { model.hlsReplayClosed() } }
        )) {
            if let replay = model.activeHLSReplay {
                HLSReplayPlayerView(url: replay.url, startDate: replay.startDate)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.activeMediathekURL != nil },
            set: { if !$0 { model.mediathekPlayClosed() } }
        )) {
            if let url = model.activeMediathekURL {
                MediathekPlayer(url: url, subtitleURL: model.activeMediathekSubtitle)
            }
        }
        #else
        .sheet(isPresented: $model.showMediathek, onDismiss: { model.mediathekClosed() }) {
            MediathekView(settings: model.settings)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .sheet(isPresented: $model.showEPGOverview) {
            EPGOverviewView(model: model, player: player, scanner: model.epgScanner)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .sheet(isPresented: Binding(
            get: { model.activeHLSReplay != nil },
            set: { if !$0 { model.hlsReplayClosed() } }
        )) {
            if let replay = model.activeHLSReplay {
                HLSReplayPlayerView(url: replay.url, startDate: replay.startDate)
                    .frame(minWidth: 1100, minHeight: 720)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.activeMediathekURL != nil },
            set: { if !$0 { model.mediathekPlayClosed() } }
        )) {
            if let url = model.activeMediathekURL {
                MediathekPlayer(url: url, subtitleURL: model.activeMediathekSubtitle)
                    .frame(minWidth: 1100, minHeight: 720)
            }
        }
        #endif
        .sheet(isPresented: Binding(
            get: { model.searchResultDialog != nil },
            set: { if !$0 { model.searchResultDialog = nil } }
        )) {
            if let dialog = model.searchResultDialog {
                MediathekSearchResultsView(title: dialog.title, results: dialog.results) { url in
                    let subtitle = dialog.results.first { $0.bestPlaybackURL == url }?.subtitleURL
                    model.playMediathekResult(url: url, subtitleURL: subtitle)
                }
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
            }
        }
        .task { await model.load() }
        .onChange(of: player.nowPlaying) { _, _ in model.programChanged() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: player.stop()
            case .active: model.resume()
            default: break
            }
        }
        #if os(tvOS)
        .onChange(of: player.status) { _, status in
            if status == .playing, model.settings.match50Hz {
                DisplayCriteria.request50Hz()
            }
        }
        #endif
    }
}

/// Alles, was über dem Bild liegt.
struct OverlayLayer: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController

    var body: some View {
        ZStack {
            switch model.loadState {
            case .loading:
                StatusCard(title: "Verbinde mit der FRITZ!Box …", message: nil, hint: nil, busy: true)
            case .failed(let message):
                StatusCard(title: "Keine Verbindung", message: message,
                           hint: "\(UI.select): erneut versuchen · \(UI.playPause): Einstellungen", busy: false)
            case .ready:
                readyLayer
            }
        }
    }

    @ViewBuilder private var readyLayer: some View {
        if case .failed(let title, let message, let hint) = player.status {
            StatusCard(title: title, message: message,
                       hint: hint ?? "\(UI.upDown): anderer Sender · \(UI.back): Senderliste", busy: false)
        } else if case .reconnecting(let seconds) = player.status {
            StatusCard(title: "Verbindung unterbrochen", message: "Neuer Versuch in \(seconds) s …",
                       hint: "Bleibt das Bild weg: Sind alle 4 Tuner der FRITZ!Box belegt?", busy: true)
        } else if player.status == .connecting {
            ProgressView().scaleEffect(1.5)
        }

        if model.overlay == .none {
            if player.isTimeshifted {
                TimeshiftBar(model: model, player: player)
            } else if model.bannerVisible {
                InfoBanner(model: model, player: player)
            }
        }

        switch model.overlay {
        case .none:
            EmptyView()
        case .info(let selection):
            InfoPanel(model: model, player: player, selection: selection)
        case .channelList(let selectedID, let moving):
            ChannelListOverlay(model: model, player: player, selectedID: selectedID, moving: moving)
        case .directEntry(let digits, let key):
            DirectEntryOverlay(model: model, digits: digits, key: key)
        }
    }
}
