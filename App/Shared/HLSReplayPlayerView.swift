import SwiftUI
import AVKit

/// Spielt den offiziellen HLS-Livestream eines Senders ab (Funktion „Von Anfang an“).
/// Startet nach Möglichkeit am Anfang der Sendung (`startDate` über EXT-X-PROGRAM-DATE-TIME).
struct HLSReplayPlayerView: View {
    let url: URL
    let startDate: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                if let start = startDate {
                    item.seek(to: start, completionHandler: { _ in
                        player.play()
                    })
                } else {
                    player.play()
                }
            }
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
}
