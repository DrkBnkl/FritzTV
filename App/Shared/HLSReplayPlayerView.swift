import SwiftUI
import AVKit

/// Spielt den offiziellen HLS-Livestream eines Senders ab (Funktion „Von Anfang an“).
/// Springt an den Anfang der Sendung über die Uhrzeit im Stream (EXT-X-PROGRAM-DATE-TIME).
/// Reicht das Rückspulfenster des Senders nicht so weit zurück, beginnt die Wiedergabe am
/// frühesten verfügbaren Punkt.
struct HLSReplayPlayerView: View {
    let url: URL
    let startDate: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .task { await start() }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                Button("Live") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding()
            }
            #endif
    }

    @MainActor
    private func start() async {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        guard let startDate else {
            player.play()
            return
        }

        // seek(to: Date) funktioniert erst, wenn das Element bereit ist und die Playlist
        // mit Uhrzeiten geladen wurde. Höchstens 10 Sekunden warten.
        for _ in 0..<100 where item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay else {
            player.play()
            return
        }

        let reached: Bool = await withCheckedContinuation { continuation in
            // seek(to: Date) gibt sofort false zurück, wenn der Zeitpunkt nicht im Stream liegt;
            // ob dann noch der Rückruf kommt, ist nicht garantiert. Daher nur einmal fortsetzen.
            let once = ResumeOnce(continuation)
            let started = item.seek(to: startDate) { finished in once.resume(finished) }
            if !started { once.resume(false) }
        }
        if !reached, let earliest = item.seekableTimeRanges.first?.timeRangeValue.start {
            DebugLog.log("Von Anfang an: Sendungsbeginn liegt vor dem Rückspulfenster, starte am frühesten Punkt")
            _ = await player.seek(to: earliest)
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
