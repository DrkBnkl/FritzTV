import SwiftUI
import FritzTVKit
#if os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.scenePhase) private var scenePhase
    /// Platz für das Live-Bild in der Programmübersicht (Bildschirmkoordinaten), sonst `nil`.
    @State private var epgPreviewFrame: CGRect?
    #if os(macOS)
    @State private var singleClickTask: Task<Void, Never>?
    @StateObject private var controls = MacControlsState()
    #endif

    private var previewFrame: CGRect? { model.showEPGOverview ? epgPreviewFrame : nil }

    var body: some View {
        GeometryReader { windowGeo in
            ZStack {
                Color.black.ignoresSafeArea()
                // Die Programmübersicht liegt UNTER der Bildfläche. Sie wird nur eingeblendet,
                // wenn sie aktiv ist, um im normalen TV-Betrieb und in der Senderliste maximale Performance zu garantieren.
                if model.showEPGOverview && model.activeHLSReplay == nil && model.activeMediathekURL == nil {
                    EPGOverviewView(model: model, player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // In der Programmübersicht läuft das Bild verkleinert im Vorschaufenster weiter.
                // Dieselbe Ansicht wird nur verschoben (kein zweiter Player, kein Neuaufbau).
                PlayerSurface(player: player.mediaPlayer, previewFrame: previewFrame, dockLivePreview: model.settings.dockLivePreview, zoom: player.liveZoom)
                    .modifier(EPGPreviewPlacement(
                        frame: previewFrame,
                        channelText: model.currentEntry.map { "\($0.number) · \($0.group.displayName)" } ?? "Live-TV",
                        showOverlay: true
                    ))
                // Schwarzer Bildschirm beim Umschalten: Blendet Standbilder des alten Senders aus,
                // bis der neue Sender ein Bild zeigt. Aus der Programmübersicht immer – das kleine
                // Vorschaubild wächst sonst kurz mit dem alten Sender auf Vollbild.
                if (model.settings.blackScreenOnZap || model.zapFromEPG)
                    && (player.status.isTransitioning || player.awaitingFirstPicture)
                    && !player.isReplaying && !model.showEPGOverview {
                    Color.black.ignoresSafeArea()
                }
                // Timeshift: Mitschnitt-Wiedergabe liegt über dem stumm weiterlaufenden Live-Bild.
                PlayerSurface(player: player.replayPlayer, previewFrame: previewFrame, dockLivePreview: model.settings.dockLivePreview, zoom: player.replayZoom)
                    .opacity(player.isReplaying ? 1 : 0)
                    .allowsHitTesting(false)
                    .modifier(EPGPreviewPlacement(frame: previewFrame, showOverlay: false))
                if let replay = model.activeHLSReplay {
                    HLSReplayPlayerView(url: replay.url, startDate: replay.startDate, volume: model.outputVolume) {
                        model.hlsReplayClosed()
                    }
                    .ignoresSafeArea()
                } else if let url = model.activeMediathekURL {
                    MediathekPlayer(url: url, subtitleURL: model.activeMediathekSubtitle, volume: model.outputVolume) {
                        model.mediathekPlayClosed()
                    }
                    .ignoresSafeArea()
                } else if !model.showEPGOverview {
                    #if os(macOS)
                    // Mausbedienung im Live-Bild auf dem Mac:
                    // - Doppelklick: Vollbild umschalten
                    // - Einfacher Klick: Senderliste öffnen
                    // - Rechtsklick: Kontextmenü mit allen Aktionen
                    // - Mausbewegung: Steuerleiste einblenden, nach 3 s Ruhe Leiste und Mauszeiger ausblenden
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: controls.pointerMoved()
                            case .ended: controls.pointerLeft()
                            }
                        }
                        .onTapGesture(count: 2) {
                            singleClickTask?.cancel()
                            NSApp.keyWindow?.toggleFullScreen(nil)
                        }
                        .onTapGesture {
                            singleClickTask?.cancel()
                            singleClickTask = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled else { return }
                                if model.overlay == .none {
                                    model.handle(.back)
                                }
                            }
                        }
                        .contextMenu {
                            macContextMenu
                        }
                    #endif
                    OverlayLayer(model: model, player: player)
                    #if os(macOS)
                    if showsControlBar {
                        MacControlBar(model: model, player: player, controls: controls)
                            .transition(.opacity)
                    }
                    #endif
                }
            }
            .environment(\.windowSize, windowGeo.size)
            #if os(macOS)
            .background(WindowButtonsFader(visible: showsWindowButtons))
            #endif
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
            if model.showSettings {
                SettingsView(model: model, settings: model.settings)
            }
        }
        #else
        .sheet(isPresented: $model.showSettings, onDismiss: { model.applySettings() }) {
            if model.showSettings {
                SettingsView(model: model, settings: model.settings)
            }
        }
        #endif
        .searchResultsPresentation(isPresented: Binding(
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
            if case .failed = newStatus { model.zapFromEPG = false }
            #if os(tvOS)
            if newStatus == .playing, model.settings.match50Hz {
                DisplayCriteria.request50Hz()
            }
            #endif
        }
        .onChange(of: player.awaitingFirstPicture) { _, waiting in
            if !waiting { model.zapFromEPG = false }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: player.stop()
            case .active:
                model.returnedToForeground()
                KeepAwake.reassert(for: player.status)
            default: break
            }
        }
        #if os(macOS)
        .onAppear {
            controls.allowsCursorHiding = { [model] in model.isPlainLiveView }
        }
        .onDisappear {
            singleClickTask?.cancel()
            player.stop()
            KeepAwake.update(for: .idle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            player.stop()
            KeepAwake.update(for: .idle)
        }
        #endif
    }

    #if os(macOS)
    /// Steuerleiste im Live-Bild: bei Mausbewegung, nach dem Umschalten und solange angehalten.
    private var showsControlBar: Bool {
        guard model.loadState == .ready, model.overlay == .none else { return false }
        return controls.pointerActive || model.bannerVisible || player.pausedSince != nil
    }

    /// Fensterknöpfe: mit der Steuerleiste, und immer, solange etwas anderes als das Bild zu sehen ist.
    /// Im Vollbild blendet macOS die Titelleiste selbst ein und aus; die Knöpfe bleiben dort sichtbar.
    private var showsWindowButtons: Bool {
        !model.isPlainLiveView || showsControlBar || controls.isFullScreen
    }

    @ViewBuilder
    private var macContextMenu: some View {
        Button {
            model.openEPGOverview()
        } label: {
            Label("Programmübersicht (Zeitstrahl)", systemImage: "calendar.day.timeline.left")
        }

        Button {
            model.openInfoPanel()
        } label: {
            Label("Sendungsinfo einblenden", systemImage: "info.circle")
        }

        Button {
            model.openChannelList()
        } label: {
            Label("Senderliste", systemImage: "list.bullet")
        }

        Divider()

        Button {
            player.togglePause()
            model.showBanner()
        } label: {
            Label(player.pausedSince != nil ? "Weiterlaufen" : "Anhalten (Timeshift)",
                  systemImage: player.pausedSince != nil ? "play.fill" : "pause.fill")
        }

        if player.isTimeshifted {
            Button {
                player.goLive()
            } label: {
                Label("Zum Live-Bild springen", systemImage: "dot.radiowaves.left.and.right")
            }
        }

        if let entry = model.currentEntry, let hls = PublicHLSChannels.hlsURL(for: entry.group.key) {
            Button {
                let start = player.displayedProgram?.startDate
                model.startHLSReplay(url: hls, startDate: start)
            } label: {
                Label("Von Anfang an abspielen", systemImage: "clock.arrow.circlepath")
            }
        }

        if let title = player.displayedProgram?.title ?? player.nowPlaying, !title.isEmpty {
            Button {
                model.searchMediathek(title: title, channel: model.currentEntry?.group.displayName)
            } label: {
                Label("In Mediathek suchen", systemImage: "magnifyingglass")
            }
        }

        Divider()

        Button {
            model.stepChannel(+1)
        } label: {
            Label("Nächster Sender", systemImage: "forward.fill")
        }

        Button {
            model.stepChannel(-1)
        } label: {
            Label("Voriger Sender", systemImage: "backward.fill")
        }

        Button {
            player.cycleAudioTrack()
            model.showBanner()
        } label: {
            Label("Tonspur wechseln (\(player.audioTrackName))", systemImage: "speaker.wave.2")
        }

        Button {
            player.cycleSubtitle()
            model.showBanner()
        } label: {
            Label("Untertitel wechseln (\(player.subtitleName))", systemImage: "captions.bubble")
        }

        Divider()

        Button {
            NSApp.keyWindow?.toggleFullScreen(nil)
        } label: {
            Label("Vollbild umschalten", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            model.showSettings = true
        } label: {
            Label("Einstellungen…", systemImage: "gearshape")
        }
    }
    #endif
}

/// Alles, was über dem Bild liegt.
struct OverlayLayer: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController

    var body: some View {
        ZStack {
            switch model.loadState {
            case .loading:
                // Apple-Richtlinien: schwarzer Bildschirm mit zentriertem Ladesymbol, ohne weitere Inhalte.
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
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

        // Auf dem Mac übernimmt die Steuerleiste (`MacControlBar`) Infoleiste und Timeshift-Leiste.
        #if !os(macOS)
        if model.overlay == .none {
            if player.isTimeshifted {
                if player.pausedSince != nil || model.bannerVisible {
                    TimeshiftBar(model: model, player: player)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else if model.bannerVisible {
                InfoBanner(model: model, player: player)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #endif

        switch model.overlay {
        case .none:
            EmptyView()
        case .info(let selection):
            InfoPanel(model: model, player: player, selection: selection)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .footer(let index):
            ChannelFooter(model: model, player: player, index: index)
        case .channelList(let selectedID):
            ChannelListOverlay(model: model, player: player, selectedID: selectedID)
        case .directEntry(let digits, let key):
            DirectEntryOverlay(model: model, digits: digits, key: key)
        }

        if let feedback = player.jumpFeedback {
            Text(feedback)
                .font(UI.font(44, .bold))
                .foregroundStyle(UI.text)
                .padding(.horizontal, UI.s(36))
                .padding(.vertical, UI.s(18))
                .background(Color.black.opacity(0.75), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: UI.s(2)))
                .shadow(color: .black.opacity(0.5), radius: 8)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private extension View {
    /// Mediathek-Suchergebnisse: auf dem Apple TV im Vollbild (als Sheet war das Fenster klein,
    /// die Schrift winzig und das Fernsehbild schien durch), auf dem Mac als Sheet.
    @ViewBuilder
    func searchResultsPresentation<Content: View>(isPresented: Binding<Bool>,
                                                  @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(tvOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
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
/// Apple TV: Die SwiftUI-Modifier bleiben immer gleich; verkleinert wird in
/// `VideoHostView` per UIKit-Transformation (siehe dort, warum).
/// Mac: Die Fläche behält die volle Größe und wird passgenau verkleinert und positioniert,
/// ohne ihre Identität zu verlieren (kein Player-Neuaufbau, unterbrechungsfreier Ton).
struct EPGPreviewPlacement: ViewModifier {
    let frame: CGRect?
    var channelText: String? = nil
    var showOverlay: Bool = true

    func body(content: Content) -> some View {
        #if os(macOS)
        GeometryReader { geo in
            let full = geo.size
            let isPreview = frame != nil
            let targetFrame = frame ?? CGRect(origin: .zero, size: full)
            let scaleX = targetFrame.width / max(full.width, 1)
            let scaleY = targetFrame.height / max(full.height, 1)

            ZStack(alignment: .topLeading) {
                content
                    .frame(width: full.width, height: full.height)
                    .scaleEffect(x: scaleX, y: scaleY, anchor: .topLeading)
                    .frame(width: targetFrame.width, height: targetFrame.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: isPreview ? 12 : 0, style: .continuous))

                if isPreview && showOverlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(EPGColors.accent, lineWidth: 2)

                    if let channelText {
                        HStack(spacing: 6) {
                            Circle().fill(EPGColors.liveGreen).frame(width: 8, height: 8)
                            Text(channelText)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(EPGColors.text)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(10)
                    }
                }
            }
            .frame(width: targetFrame.width, height: targetFrame.height)
            .offset(x: targetFrame.minX, y: targetFrame.minY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(frame == nil)
        #else
        content
            .ignoresSafeArea()
            .allowsHitTesting(false)
        #endif
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
    #elseif os(tvOS)
    /// tvOS verwirft `isIdleTimerDisabled` gelegentlich intern (der Wert bleibt `true`, der
    /// Bildschirmschoner kommt trotzdem). Solange live gespielt wird, deshalb regelmäßig neu setzen.
    private static var refreshTimer: Timer?
    #endif

    /// Erneut anwenden, z. B. wenn die App wieder aktiv wird.
    static func reassert(for status: PlayerStatus) {
        #if os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        update(for: status)
    }

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
        if awake, refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                MainActor.assumeIsolated {
                    // Umschalten zwingt das System, die Sperre neu zu übernehmen.
                    UIApplication.shared.isIdleTimerDisabled = false
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        } else if !awake, let timer = refreshTimer {
            timer.invalidate()
            refreshTimer = nil
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

/// Schlüssel im SwiftUI-Environment für die aktuelle Fenstergröße des Inhaltsbereichs.
/// Auf dem Mac reagieren Overlays dadurch dynamisch auf kleine/kompakte Fenstergrößen.
struct WindowSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = CGSize(width: 1920, height: 1080)
}

extension EnvironmentValues {
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}
