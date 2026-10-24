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
            OverlayLayer(model: model, player: player)
        }
        .modifier(RemoteInputModifier(model: model))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showSettings, onDismiss: { model.applySettings() }) {
            SettingsView(model: model, settings: model.settings)
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $model.showMediathek, onDismiss: { model.mediathekClosed() }) {
            MediathekView(settings: model.settings)
        }
        #else
        .sheet(isPresented: $model.showMediathek, onDismiss: { model.mediathekClosed() }) {
            MediathekView(settings: model.settings)
                .frame(minWidth: 1100, minHeight: 720)
        }
        #endif
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
        if case .reconnecting(let seconds) = player.status {
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
        case .channelList(let selection, let moving):
            ChannelListOverlay(model: model, player: player, selection: selection, moving: moving)
        case .directEntry(let digits, let key):
            DirectEntryOverlay(model: model, digits: digits, key: key)
        }
    }
}
