import SwiftUI
import AVKit
import FritzTVKit
#if os(macOS)
import AppKit
#endif

/// Spielt den offiziellen HLS-Livestream eines Senders ab (Funktion „Von Anfang an“).
/// Springt an den Anfang der Sendung über die Uhrzeit im Stream (EXT-X-PROGRAM-DATE-TIME).
/// Liegt der Beginn vor dem Rückspulfenster des Senders oder ist kein Startdatum bekannt,
/// beginnt die Wiedergabe am frühesten verfügbaren Punkt des HLS-Puffers.
struct HLSReplayPlayerView: View {
    let url: URL
    let startDate: Date?
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var jumpFeedback: String?
    @State private var jumpFeedbackTask: Task<Void, Never>?
    @State private var lastJumpPressAt = Date.distantPast
    @State private var lastJumpForward = true
    @State private var jumpPressCount = 0
    /// Hinweise oben („Live-TV“ / „Von Anfang an“) blenden sich nach einigen Sekunden aus und
    /// erscheinen bei jeder Bedienung kurz wieder.
    @State private var headerVisible = true
    @State private var headerTask: Task<Void, Never>?

    var body: some View {
        playerView
            .ignoresSafeArea()
            .task { await start() }
            .onAppear { showHeader() }
            .onDisappear {
                jumpFeedbackTask?.cancel()
                headerTask?.cancel()
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .hlsReplayJump)) { notification in
                if let forward = notification.object as? Bool {
                    jumpProgressive(forward: forward)
                } else if let seconds = notification.object as? Double {
                    jumpProgressive(forward: seconds > 0)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .hlsReplayTogglePause)) { _ in
                togglePlayPause()
            }
            .overlay(alignment: .center) {
                if let jumpFeedback {
                    Text(jumpFeedback)
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
            .overlay(alignment: .top) {
                HStack(alignment: .center) {
                    Button(action: close) {
                        HStack(spacing: UI.s(12)) {
                            Image(systemName: "chevron.left")
                                .font(UI.font(24, .bold))
                            Text("Live-TV")
                                .font(UI.font(26, .semibold))
                            #if os(macOS)
                            Text("Esc")
                                .font(UI.font(20, .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            #endif
                        }
                        .foregroundStyle(UI.text)
                        .padding(.horizontal, UI.s(26))
                        .padding(.vertical, UI.s(14))
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: UI.s(2)))
                        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut(.escape, modifiers: [])
                    .onHover { inside in
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    #endif

                    Spacer()

                    HStack(spacing: UI.s(12)) {
                        Circle()
                            .fill(UI.accent)
                            .frame(width: UI.s(14), height: UI.s(14))
                        Text("Von Anfang an")
                            .font(UI.font(24, .medium))
                            .foregroundStyle(UI.text.opacity(0.9))
                    }
                    .padding(.horizontal, UI.s(24))
                    .padding(.vertical, UI.s(12))
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: UI.s(1.5)))
                }
                .padding(.horizontal, UI.s(36))
                .padding(.top, UI.s(28))
                .opacity(headerVisible ? 1 : 0)
                .allowsHitTesting(headerVisible)
            }
            #if os(macOS)
            .onContinuousHover { phase in
                if case .active = phase {
                    showHeader(paused: player.timeControlStatus == .paused)
                }
            }
            .onKeyPress(.escape) {
                close()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                jumpProgressive(forward: false)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                jumpProgressive(forward: true)
                return .handled
            }
            .onKeyPress(.space) {
                togglePlayPause()
                return .handled
            }
            #elseif os(tvOS)
            .onExitCommand {
                close()
            }
            #endif
    }

    @ViewBuilder
    private var playerView: some View {
        #if os(macOS)
        MacAVPlayerView(player: player)
        #else
        VideoPlayer(player: player)
        #endif
    }

    private func showHeader(paused: Bool = false) {
        withAnimation(.easeOut(duration: 0.2)) { headerVisible = true }
        headerTask?.cancel()
        guard !paused else { return }
        headerTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { headerVisible = false }
        }
    }

    private func jumpProgressive(forward: Bool) {
        showHeader(paused: player.timeControlStatus == .paused)
        let step = ProgressiveJump.nextStep(
            forward: forward,
            lastPressAt: &lastJumpPressAt,
            lastDirectionForward: &lastJumpForward,
            pressCount: &jumpPressCount
        )
        jump(seconds: step.stepDelta, display: step.displayText)
    }

    private func jump(seconds: Double, display: String? = nil) {
        let current = player.currentTime()
        let delta = CMTime(seconds: seconds, preferredTimescale: 600)
        let target = CMTimeAdd(current, delta)

        if let range = player.currentItem?.seekableTimeRanges.first?.timeRangeValue {
            let start = range.start
            let end = CMTimeAdd(range.start, range.duration)
            var clamped = target
            if target < start {
                clamped = start
            } else if target > end {
                clamped = end
            }
            player.seek(to: clamped, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        let label = display ?? (seconds > 0 ? "+\(Int(seconds)) s" : "\(Int(seconds)) s")
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            jumpFeedback = label
        }
        jumpFeedbackTask?.cancel()
        jumpFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) {
                    jumpFeedback = nil
                }
            }
        }
    }

    private func togglePlayPause() {
        if player.timeControlStatus == .paused {
            player.play()
            showHeader(paused: false)
        } else {
            player.pause()
            showHeader(paused: true)
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func start() async {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        // 1. Warten, bis das HLS-Element bereit ist (maximal 10 Sekunden)
        for _ in 0..<100 where item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay else {
            player.play()
            return
        }

        // 2. Warten, bis die Puffergrenzen (seekableTimeRanges) vorliegen
        for _ in 0..<30 where item.seekableTimeRanges.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }

        var seekSucceeded = false

        // 3. Wenn ein Sendungsbeginn bekannt ist, versuche per Datum an den Beginn zu springen
        if let startDate {
            seekSucceeded = await withCheckedContinuation { continuation in
                let once = ResumeOnce(continuation)
                let started = item.seek(to: startDate) { finished in once.resume(finished) }
                if !started { once.resume(false) }
            }
            if seekSucceeded {
                DebugLog.log("Von Anfang an: Erfolgreich an Sendungsbeginn (\(startDate.formatted(date: .omitted, time: .standard))) gesprungen")
            }
        }

        // 4. Wenn seek(to: startDate) fehlgeschlagen ist (z. B. Beginn liegt vor dem 2h-Puffer)
        // oder kein Startdatum vorliegt, springe an den frühestmöglichen Zeitpunkt des HLS-Puffers
        if !seekSucceeded, let earliest = item.seekableTimeRanges.first?.timeRangeValue.start {
            DebugLog.log("Von Anfang an: Springe an frühestmöglichen Punkt im HLS-Puffer (\(Int(earliest.seconds)) s)")
            _ = await player.seek(to: earliest, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        player.play()
    }
}

/// Setzt eine Continuation höchstens einmal fort.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

extension Notification.Name {
    static let hlsReplayJump = Notification.Name("FritzTV_hlsReplayJump")
    static let hlsReplayTogglePause = Notification.Name("FritzTV_hlsReplayTogglePause")
    static let mediathekJump = Notification.Name("FritzTV_mediathekJump")
    static let mediathekTogglePause = Notification.Name("FritzTV_mediathekTogglePause")
    static let searchResultMove = Notification.Name("FritzTV_searchResultMove")
    static let searchResultSelect = Notification.Name("FritzTV_searchResultSelect")
}

#if os(macOS)
/// Direkte Einbettung von `AVPlayerView` aus `AVKit` für macOS.
/// Vermeidet einen Swift-Runtime-Absturz in `_AVKit_SwiftUI` (`getSuperclassMetadata`),
/// wenn `AVKit.framework` beim Linken von `VideoPlayer` nicht automatisch geladen wurde.
struct MacAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> MacAVPlayerHostView {
        let host = MacAVPlayerHostView()
        host.playerView.player = player
        return host
    }

    func updateNSView(_ nsView: MacAVPlayerHostView, context: Context) {
        if nsView.playerView.player !== player {
            nsView.playerView.player = player
        }
    }
}

final class MacAVPlayerHostView: NSView {
    let playerView = AVPlayerView()
    private var windowObservers: [NSObjectProtocol] = []
    private var snapshotTimer: Timer?
    private var crossfadeTimer: Timer?
    private var lastSnapshotImage: NSImage?
    private var dockLivePreview: Bool {
        UserDefaults.standard.object(forKey: "dockLivePreview") != nil ? UserDefaults.standard.bool(forKey: "dockLivePreview") : true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.autoresizingMask = [.width, .height]
        playerView.frame = bounds
        addSubview(playerView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    override func layout() {
        super.layout()
        if playerView.frame != bounds {
            playerView.frame = bounds
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        stopSnapshotTimer()
        guard let window else { return }
        window.miniwindowImage = nil
        window.dockTile.contentView = nil
        window.dockTile.display()

        let nc = NotificationCenter.default
        windowObservers.append(
            nc.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleWillMiniaturize()
            }
        )
        windowObservers.append(
            nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleDidMiniaturize()
            }
        )
        windowObservers.append(
            nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleDidDeminiaturize()
            }
        )

        startSnapshotTimer()
    }

    private func startSnapshotTimer() {
        stopSnapshotTimer()
        // Nach Wiedergabebeginn zeitnah erstes Standbild sichern
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.performSnapshotCheck()
        }
        // Regelmäßig im Hintergrund ein aktuelles Standbild für das Dock-Icon vorhalten.
        // Intervall: 12 Sekunden (angenehm ruhig, kein nerviges Stroboskop/Flimmern im Augenwinkel).
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { [weak self] _ in
            self?.performSnapshotCheck()
        }
    }

    private func stopSnapshotTimer() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    private func performSnapshotCheck() {
        guard let player = playerView.player,
              player.timeControlStatus == .playing else { return }
        if let window, window.isMiniaturized, !dockLivePreview {
            return
        }
        guard let snapshot = captureSnapshot() else { return }
        let fitted = snapshot.aspectFittedForDock()
        if let window, window.isMiniaturized {
            if dockLivePreview {
                transitionToDockImage(fitted)
            }
        } else {
            lastSnapshotImage = fitted
        }
    }

    private func ensureDockImageView() -> NSImageView? {
        guard let window else { return nil }
        if let iv = window.dockTile.contentView as? NSImageView {
            return iv
        }
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        iv.imageScaling = .scaleProportionallyUpOrDown
        window.dockTile.contentView = iv
        return iv
    }

    private func applyDockImage(_ image: NSImage) {
        guard let window else { return }
        window.miniwindowImage = image
        if let iv = ensureDockImageView() {
            iv.image = image
            window.dockTile.display()
        }
    }

    private func transitionToDockImage(_ newImage: NSImage) {
        guard let window, window.isMiniaturized else {
            lastSnapshotImage = newImage
            applyDockImage(newImage)
            return
        }

        crossfadeTimer?.invalidate()

        guard let fromImage = lastSnapshotImage else {
            lastSnapshotImage = newImage
            applyDockImage(newImage)
            return
        }

        // Sanfter Übergang: 10 Schritte à 80 ms = 800 ms Gesamtdauer.
        // Keine harten Sprünge, kein Flackern im Augenwinkel.
        let steps = 10
        let stepDuration = 0.08
        var currentStep = 0

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self, let win = self.window, win.isMiniaturized else {
                timer.invalidate()
                return
            }
            currentStep += 1
            let progress = min(1.0, CGFloat(currentStep) / CGFloat(steps))
            let blended = fromImage.crossfaded(with: newImage, progress: progress)
            self.applyDockImage(blended)

            if currentStep >= steps {
                timer.invalidate()
                self.crossfadeTimer = nil
                self.lastSnapshotImage = newImage
            }
        }
    }

    private func captureSnapshot() -> NSImage? {
        if let asset = playerView.player?.currentItem?.asset,
           let currentTime = playerView.player?.currentTime() {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            if let cgImage = try? generator.copyCGImage(at: currentTime, actualTime: nil) {
                return NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180))
            }
        }
        if let rep = playerView.bitmapImageRepForCachingDisplay(in: playerView.bounds) {
            playerView.cacheDisplay(in: playerView.bounds, to: rep)
            let image = NSImage(size: playerView.bounds.size)
            image.addRepresentation(rep)
            return image
        }
        return nil
    }

    private func handleWillMiniaturize() {
        guard let window else { return }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        if let snapshot = captureSnapshot() {
            let fitted = snapshot.aspectFittedForDock()
            lastSnapshotImage = fitted
            applyDockImage(fitted)
        } else if let last = lastSnapshotImage {
            applyDockImage(last)
        }
    }

    private func handleDidMiniaturize() {
        if let window, window.miniwindowImage == nil, let last = lastSnapshotImage {
            applyDockImage(last)
        }
        playerView.isHidden = true
    }

    private func handleDidDeminiaturize() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        playerView.isHidden = false
        window?.miniwindowImage = nil
        if let window {
            window.dockTile.contentView = nil
            window.dockTile.display()
        }
        playerView.frame = bounds
        playerView.needsLayout = true
        playerView.needsDisplay = true
    }

    private func removeObservers() {
        for obs in windowObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        windowObservers.removeAll()
    }

    deinit {
        stopSnapshotTimer()
        removeObservers()
    }
}
#endif
