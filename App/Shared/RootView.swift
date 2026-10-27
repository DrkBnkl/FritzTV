import SwiftUI
import FritzTVKit
#if os(tvOS)
import UIKit
#endif

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.scenePhase) private var scenePhase
    /// Platz für das Live-Bild in der Programmübersicht (Bildschirmkoordinaten), sonst `nil`.
    @State private var epgPreviewFrame: CGRect?

    private var previewFrame: CGRect? { model.showEPGOverview ? epgPreviewFrame : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // In der Programmübersicht läuft das Bild verkleinert im Vorschaufenster weiter.
            // Dieselbe Ansicht wird nur verschoben (kein zweiter Player, kein Neuaufbau).
            PlayerSurface(player: player.mediaPlayer)
                .modifier(EPGPreviewPlacement(frame: previewFrame))
            // Schwarzer Bildschirm beim Umschalten: Blendet Standbilder des alten Senders aus,
            // bis der neue Stream decodiert wird.
            if model.settings.blackScreenOnZap && player.status.isTransitioning && !player.isReplaying {
                Color.black.ignoresSafeArea()
            }
            // Timeshift: Mitschnitt-Wiedergabe liegt über dem stumm weiterlaufenden Live-Bild.
            PlayerSurface(player: player.replayPlayer)
                .opacity(player.isReplaying ? 1 : 0)
                .allowsHitTesting(false)
                .modifier(EPGPreviewPlacement(frame: previewFrame))
            if let replay = model.activeHLSReplay {
                HLSReplayPlayerView(url: replay.url, startDate: replay.startDate) {
                    model.hlsReplayClosed()
                }
                .ignoresSafeArea()
            } else if let url = model.activeMediathekURL {
                MediathekPlayer(url: url, subtitleURL: model.activeMediathekSubtitle) {
                    model.mediathekPlayClosed()
                }
                .ignoresSafeArea()
            } else if model.showEPGOverview {
                EPGOverviewView(model: model, player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                #if os(macOS)
                // Mausklick ins Bild öffnet die Senderliste. Nur auf dem Mac: Auf dem Apple TV fing
                // diese Fläche den Klick der Fernbedienung ab (z. B. im Timeshift).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.overlay == .none {
                            model.handle(.back)
                        }
                    }
                #endif
                OverlayLayer(model: model, player: player)
            }
        }
        .onPreferenceChange(EPGPreviewFrameKey.self) { epgPreviewFrame = $0 }
        .modifier(RemoteInputModifier(model: model))
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            model.handleDeepLink(url: url)
        }
        #if os(tvOS)
        // Vollbild statt Sheet: Das halbdurchsichtige Sheet lag über dem laufenden Bild und machte
        // die Einstellungen schwer lesbar.
        .fullScreenCover(isPresented: $model.showSettings, onDismiss: { model.applySettings() }) {
            SettingsView(model: model, settings: model.settings)
        }
        #else
        .sheet(isPresented: $model.showSettings, onDismiss: { model.applySettings() }) {
            SettingsView(model: model, settings: model.settings)
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $model.showMediathek, onDismiss: { model.mediathekClosed() }) {
            MediathekView(settings: model.settings)
        }
        #else
        .sheet(isPresented: $model.showMediathek, onDismiss: { model.mediathekClosed() }) {
            MediathekView(settings: model.settings)
                .frame(minWidth: 1000, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
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
                .frame(minWidth: 600, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
                #endif
            }
        }
        .task { await model.load() }
        .onChange(of: player.nowPlaying) { _, _ in model.programChanged() }
        .onChange(of: player.currentProgram) { _, _ in model.programChanged() }
        .onChange(of: player.status) { oldStatus, newStatus in
            KeepAwake.update(for: newStatus)
            if oldStatus != .playing && newStatus == .playing {
                model.showBanner()
            }
            #if os(tvOS)
            if newStatus == .playing, model.settings.match50Hz {
                DisplayCriteria.request50Hz()
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: player.stop()
            case .active: model.returnedToForeground()
            default: break
            }
        }
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
        } else if case .reconnecting(let seconds) = player.status, !player.isReplaying {
            // Beim zeitversetzten Schauen läuft die Wiedergabe aus dem Puffer weiter; das
            // Neuverbinden im Hintergrund braucht dann keine Meldung über dem Bild.
            StatusCard(title: "Verbindung unterbrochen", message: "Neuer Versuch in \(seconds) s …",
                       hint: "Bleibt das Bild weg: Sind alle 4 Tuner der FRITZ!Box belegt?", busy: true)
        }

        if model.overlay == .none {
            if player.isTimeshifted {
                TimeshiftBar(model: model, player: player)
            } else if model.bannerVisible {
                InfoBanner(model: model, player: player)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        switch model.overlay {
        case .none:
            EmptyView()
        case .info(let selection):
            InfoPanel(model: model, player: player, selection: selection)
        case .channelList(let selectedID):
            ChannelListOverlay(model: model, player: player, selectedID: selectedID)
        case .directEntry(let digits, let key):
            DirectEntryOverlay(model: model, digits: digits, key: key)
        }

        if let feedback = player.jumpFeedback {
            Text(feedback)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.75), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.5), radius: 8)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Rahmen des Vorschaufensters in der Programmübersicht (Bildschirmkoordinaten).
struct EPGPreviewFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// Bildfläche: normalerweise bildschirmfüllend, in der Programmübersicht im Vorschaufenster.
///
/// Die Fläche behält immer die volle Bildschirmgröße und wird nur per Transformation
/// verkleinert und verschoben. So muss VLC seine Videoausgabe nicht an eine neue Größe
/// anpassen – beim Ändern der Größe blieb das Vorschaubild auf dem Apple TV stehen.
struct EPGPreviewPlacement: ViewModifier {
    let frame: CGRect?

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let full = geo.size
            let scale = frame.map { $0.width / max(full.width, 1) } ?? 1
            content
                .frame(width: full.width, height: full.height)
                .clipShape(RoundedRectangle(cornerRadius: frame == nil ? 0 : 10 / max(scale, 0.01)))
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: frame?.minX ?? 0, y: frame?.minY ?? 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(frame == nil)
        // Über die Programmübersicht legen; die Ansicht bleibt dieselbe.
        .zIndex(frame == nil ? 0 : 5)
    }
}

/// Hält Bildschirm wach, solange live gespielt wird. VLC meldet dem System – anders als Apples
/// eigene Player – keine laufende Wiedergabe, sonst springt nach einigen Minuten der
/// Bildschirmschoner (Apple TV) bzw. der Ruhezustand des Displays (Mac) an.
/// Angehalten (Timeshift) darf der Bildschirmschoner wie üblich kommen.
@MainActor
enum KeepAwake {
    #if os(macOS)
    private static var activity: NSObjectProtocol?
    #endif

    static func update(for status: PlayerStatus) {
        let awake: Bool
        switch status {
        case .playing, .connecting, .reconnecting:
            awake = true
        case .idle, .paused, .failed:
            awake = false
        }
        #if os(tvOS)
        if UIApplication.shared.isIdleTimerDisabled != awake {
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        #elseif os(macOS)
        if awake, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Live-TV läuft")
        } else if !awake, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
        #endif
    }
}
