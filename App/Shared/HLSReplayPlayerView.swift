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

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .task { await start() }
            .onDisappear {
                jumpFeedbackTask?.cancel()
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
            .overlay(alignment: .top) {
                HStack(alignment: .center) {
                    Button(action: close) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                            Text("Live-TV")
                                .font(.system(size: 15, weight: .semibold))
                            #if os(macOS)
                            Text("Esc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            #endif
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
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

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Von Anfang an")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            #if os(macOS)
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

    private func jumpProgressive(forward: Bool) {
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
        } else {
            player.pause()
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
