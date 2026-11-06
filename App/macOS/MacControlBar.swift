import SwiftUI
import AppKit
import FritzTVKit

// MARK: Ein- und Ausblenden

/// Steuert, wann Steuerleiste, Fensterknöpfe und Mauszeiger zu sehen sind: Sie erscheinen, sobald
/// sich die Maus über dem Bild bewegt, und verschwinden nach drei Sekunden Ruhe. Solange der
/// Zeiger auf der Leiste liegt, bleibt sie stehen.
@MainActor
final class MacControlsState: ObservableObject {
    @Published private(set) var pointerActive = false
    @Published private(set) var isFullScreen = false

    /// Darf der Mauszeiger ausgeblendet werden (nur im reinen Live-Bild)?
    var allowsCursorHiding: () -> Bool = { true }

    private static let idleDelay: TimeInterval = 3
    private var lastMove = Date.distantPast
    private var hideTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var hoveringBar = false {
        didSet {
            guard hoveringBar != oldValue else { return }
            if hoveringBar {
                hideTask?.cancel()
                hideTask = nil
            } else {
                pointerMoved()
            }
        }
    }

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isFullScreen = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isFullScreen = false }
            }
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Wird bei jeder Mausbewegung über dem Bild aufgerufen (oft mehrmals pro Sekunde): Es läuft
    /// nur eine Aufgabe, die bis drei Sekunden nach der letzten Bewegung wartet.
    func pointerMoved() {
        lastMove = Date()
        if !pointerActive {
            withAnimation(.easeOut(duration: 0.15)) { pointerActive = true }
        }
        guard hideTask == nil, !hoveringBar else { return }
        hideTask = Task { [weak self] in await self?.hideWhenIdle() }
    }

    /// Maus hat das Fenster verlassen: bald ausblenden.
    func pointerLeft() {
        guard !hoveringBar else { return }
        lastMove = Date().addingTimeInterval(0.6 - Self.idleDelay)
        if hideTask == nil, pointerActive {
            hideTask = Task { [weak self] in await self?.hideWhenIdle(hideCursor: false) }
        }
    }

    private func hideWhenIdle(hideCursor: Bool = true) async {
        while true {
            let remaining = lastMove.addingTimeInterval(Self.idleDelay).timeIntervalSinceNow
            if remaining <= 0 { break }
            try? await Task.sleep(for: .seconds(remaining))
            if Task.isCancelled { return }
        }
        hideTask = nil
        guard !hoveringBar else { return }
        withAnimation(.easeIn(duration: 0.3)) { pointerActive = false }
        if hideCursor, allowsCursorHiding() {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}

/// Blendet die Fensterknöpfe (Schließen, Minimieren, Vollbild) mit der Steuerleiste aus,
/// damit das Bild im Fenster ohne Titelleiste frei steht.
struct WindowButtonsFader: NSViewRepresentable {
    let visible: Bool

    final class Coordinator { var applied: Bool? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Die Bildansicht zeichnet oft neu (Player-Status): nur bei einer Änderung animieren.
        guard context.coordinator.applied != visible || nsView.window == nil else { return }
        context.coordinator.applied = visible
        let target: CGFloat = visible ? 1 : 0
        let duration = visible ? 0.15 : 0.3
        let apply = {
            guard let container = nsView.window?.standardWindowButton(.closeButton)?.superview else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                container.animator().alphaValue = target
            }
        }
        // Beim ersten Aufruf hängt die Ansicht noch in keinem Fenster.
        if nsView.window != nil { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}

// MARK: Steuerleiste

/// Schwebende Steuerleiste über dem Bild (wie QuickTime Player): Sender, laufende Sendung,
/// Timeshift-Zeitleiste, Ton und Untertitel, eigene Lautstärke, Vollbild.
struct MacControlBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @ObservedObject var controls: MacControlsState

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                header
                HStack(spacing: 14) {
                    transport
                    TimeshiftTimeline(model: model, player: player)
                    trackMenu
                    VolumeControl(model: model)
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        Image(systemName: controls.isFullScreen ? "arrow.down.right.and.arrow.up.left"
                                                                : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 20, height: 20)
                    }
                    .help(controls.isFullScreen ? "Vollbild beenden (⌃⌘F)" : "Vollbild (⌃⌘F)")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: 720)
            .onHover { controls.hoveringBar = $0 }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    // MARK: Kopfzeile

    private var header: some View {
        HStack(spacing: 8) {
            if let entry = model.currentEntry {
                ChannelLogoView(channelName: entry.group.displayName, height: 20, maxWidth: 56)
                Text("\(entry.number)  \(entry.group.displayName)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if let title = player.displayedProgram?.title ?? player.nowPlaying, !title.isEmpty {
                Text("· \(title)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let program = player.displayedProgram {
                Text("\(UI.timeFormatter.string(from: program.startDate)) – \(UI.timeFormatter.string(from: program.endDate))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: Sender und Pause

    private var transport: some View {
        HStack(spacing: 12) {
            Button { model.stepChannel(-1) } label: {
                Image(systemName: "backward.fill").frame(width: 20, height: 20)
            }
            .help("Voriger Sender (⌘←)")
            Button {
                player.togglePause()
                model.showBanner()
            } label: {
                Image(systemName: player.pausedSince != nil ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .help(player.pausedSince != nil ? "Weiter (Leertaste)" : "Anhalten (Leertaste)")
            Button { model.stepChannel(+1) } label: {
                Image(systemName: "forward.fill").frame(width: 20, height: 20)
            }
            .help("Nächster Sender (⌘→)")
        }
    }

    // MARK: Ton und Untertitel

    private var trackMenu: some View {
        Menu {
            let audio = player.audioTrackOptions
            if !audio.isEmpty {
                Picker("Tonspur", selection: Binding(get: { player.currentAudioTrackID },
                                                     set: { player.selectAudioTrack($0) })) {
                    ForEach(audio) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
            }
            Picker("Untertitel", selection: Binding(get: { player.currentSubtitleID },
                                                    set: { player.selectSubtitle($0) })) {
                ForEach(player.subtitleOptions) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tonspur: \(player.audioTrackName) · Untertitel: \(player.subtitleName)")
    }
}

// MARK: Zeitleiste

/// Timeshift-Zeitleiste: Die Breite steht für den Puffer (auf 5 Minuten gerundet), rechts ist live.
/// Grau der gepufferte Bereich, weiß bis zur gerade gezeigten Stelle. Ziehen oder Klicken springt.
private struct TimeshiftTimeline: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @State private var dragRatio: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            // Die Leiste wächst mit dem Puffer in 5-Minuten-Schritten bis zur eingestellten Länge:
            // Bei 90 Minuten wären die ersten Minuten sonst nur ein schmaler Streifen am rechten Rand.
            let limit = Double(max(model.settings.timeshiftMinutes, 1) * 60)
            let window = min(limit, max(300, (player.bufferedSeconds / 300).rounded(.up) * 300))
            let buffered = min(player.bufferedSeconds, window)
            let behind = min(player.currentBehind, window)
            let bufferStart = 1 - buffered / window
            let position = dragRatio ?? (1 - behind / window)
            let isLive = !player.isTimeshifted && dragRatio == nil

            HStack(spacing: 10) {
                Text(label(isLive: isLive, behind: dragRatio.map { (1 - $0) * window } ?? behind))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(minWidth: 44, alignment: .trailing)

                GeometryReader { geo in
                    let width = max(geo.size.width, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white.opacity(0.32))
                            .frame(width: width * (1 - bufferStart))
                            .offset(x: width * bufferStart)
                        Capsule().fill(Color.white.opacity(0.9))
                            .frame(width: max(width * (position - bufferStart), 0))
                            .offset(x: width * bufferStart)
                        if buffered > 0 {
                            Circle().fill(Color.white)
                                .frame(width: 10, height: 10)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                                .offset(x: width * position - 5)
                        }
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard buffered > 0 else { return }
                            dragRatio = min(max(value.location.x / width, bufferStart), 1)
                        }
                        .onEnded { _ in
                            if let ratio = dragRatio {
                                player.seekToBehind(seconds: (1 - ratio) * window)
                                model.showBanner()
                            }
                            dragRatio = nil
                        })
                }
                .frame(height: 18)
                .help(buffered > 0 ? "Ziehen oder klicken, um im Puffer zu springen" : "Der Puffer füllt sich, sobald das Bild läuft")

                Button { player.goLive() } label: {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isLive ? Color.white : Color.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isLive ? Color.red : Color.white.opacity(0.2), in: Capsule())
                }
                .disabled(!player.isTimeshifted)
                .help(isLive ? "Live-Bild" : "Zum Live-Bild springen (⌘L)")
            }
        }
        .frame(minWidth: 140)
    }

    private func label(isLive: Bool, behind: TimeInterval) -> String {
        if player.pausedSince != nil { return "Pause −\(Self.format(behind))" }
        return isLive ? "" : "−\(Self.format(behind))"
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: Lautstärke

/// Eigene Lautstärke wie in FritzRadio; Klick auf den Lautsprecher schaltet stumm.
private struct VolumeControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.toggleMute() } label: {
                Image(systemName: icon)
                    .frame(width: 22, height: 20, alignment: .leading)
            }
            .help(model.isMuted ? "Ton an (⌥⌘↓)" : "Ton aus (⌥⌘↓)")
            Slider(value: Binding(get: { Double(model.isMuted ? 0 : model.volume) },
                                  set: { model.volume = Int($0.rounded()) }),
                   in: 0...100)
                .controlSize(.mini)
                .frame(width: 84)
                .help("Lautstärke \(model.isMuted ? 0 : model.volume) % (⌘↑ / ⌘↓)")
        }
    }

    private var icon: String {
        let level = model.isMuted ? 0 : model.volume
        switch level {
        case 0: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
