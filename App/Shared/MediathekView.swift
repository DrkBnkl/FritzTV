import SwiftUI
import AVKit
import FritzTVKit

/// Spielt einen Mediathek-Film direkt von den Servern der Sender (MP4) mit Apples Player.
struct MediathekPlayer: View {
    let url: URL
    /// Untertitel-Datei (TTML/WebVTT), falls bekannt.
    var subtitleURL: URL? = nil
    var onClose: (() -> Void)? = nil

    @State private var player = AVPlayer()
    @State private var cues: [SubtitleCue] = []
    @State private var caption: String?
    @State private var timeObserver: Any?
    @State private var jumpFeedback: String?
    @State private var jumpFeedbackTask: Task<Void, Never>?
    @State private var lastJumpPressAt = Date.distantPast
    @State private var lastJumpForward = true
    @State private var jumpPressCount = 0
    @State private var headerVisible = true
    @State private var headerTask: Task<Void, Never>?
    @State private var playbackFailed = false
    @AppStorage("mediathekSubtitles") private var showSubtitles = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        playerView
            .ignoresSafeArea()
            .overlay {
                if playbackFailed { PlaybackFailedCard() }
            }
            .task {
                await player.waitForPlaybackFailure()
                playbackFailed = !Task.isCancelled
            }
            .overlay(alignment: .bottom) {
                if showSubtitles, let caption {
                    Text(caption)
                        .font(UI.font(38, .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, UI.s(24))
                        .padding(.vertical, UI.s(10))
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: UI.s(10)))
                        .padding(.bottom, UI.s(90))
                        .allowsHitTesting(false)
                }
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
                        Text("Mediathek")
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
            .onReceive(NotificationCenter.default.publisher(for: .mediathekJump)) { notification in
                if let forward = notification.object as? Bool {
                    jumpProgressive(forward: forward)
                } else if let seconds = notification.object as? Double {
                    jumpProgressive(forward: seconds > 0)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mediathekTogglePause)) { _ in
                togglePlayPause()
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
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
                showHeader(paused: false)
                // Untertitel zur Abspielposition nachführen (viermal pro Sekunde)
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4),
                                                              queue: .main) { time in
                    caption = SubtitleParser.text(at: time.seconds, in: cues)
                }
            }
            .task { if showSubtitles { await loadSubtitles() } }
            .onChange(of: showSubtitles) { _, enabled in
                if enabled && cues.isEmpty {
                    Task { await loadSubtitles() }
                }
            }
            .onDisappear {
                jumpFeedbackTask?.cancel()
                headerTask?.cancel()
                if let timeObserver { player.removeTimeObserver(timeObserver) }
                timeObserver = nil
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
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

    private func loadSubtitles() async {
        guard cues.isEmpty, let source = subtitleURL,
              let (data, _) = try? await URLSession.shared.data(from: source) else {
            DebugLog.log("Mediathek: keine Untertitel gefunden")
            return
        }
        cues = SubtitleParser.parse(data)
        DebugLog.log("Mediathek: \(cues.count) Untertitel geladen")
    }
}
