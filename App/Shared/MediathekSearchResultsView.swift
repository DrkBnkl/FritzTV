import SwiftUI
import FritzTVKit

/// Zeigt Suchergebnisse aus MediathekViewWeb für „Sendung verpasst“.
struct MediathekSearchResultsView: View {
    let title: String
    let results: [MediathekSearchResult]
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: UI.s(20)) {
                HStack {
                    VStack(alignment: .leading, spacing: UI.s(4)) {
                        Text("In der Mediathek gefunden").font(UI.font(36, .heavy))
                        Text("Suchbegriff: „\(title)“").font(UI.font(24)).foregroundStyle(UI.secondary)
                    }
                    Spacer()
                    Button("Schließen") { dismiss() }
                        .font(UI.font(24, .semibold))
                        #if os(macOS)
                        .keyboardShortcut(.cancelAction)
                        #endif
                }
                .padding(.horizontal, UI.s(40))
                .padding(.top, UI.s(32))

                if results.isEmpty {
                    VStack(spacing: UI.s(16)) {
                        Spacer()
                        Text("Keine passenden Sendungen in der Mediathek gefunden")
                            .font(UI.font(28, .semibold))
                            .foregroundStyle(UI.secondary)
                        Text("Manche Sendungen (z. B. Nachrichten oder lizenzierte Filme) stehen nicht in der Mediathek.")
                            .font(UI.font(22))
                            .foregroundStyle(UI.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(results) { item in
                        Button(action: {
                            if let url = item.bestPlaybackURL {
                                onSelect(url)
                                dismiss()
                            }
                        }) {
                            VStack(alignment: .leading, spacing: UI.s(8)) {
                                HStack {
                                    Text(item.channel)
                                        .font(UI.font(22, .bold))
                                        .foregroundStyle(UI.accent)
                                    if !item.topic.isEmpty {
                                        Text("· \(item.topic)")
                                            .font(UI.font(22))
                                            .foregroundStyle(UI.secondary)
                                    }
                                    Spacer()
                                    Text("\(item.duration / 60) Min.")
                                        .font(UI.font(20))
                                        .foregroundStyle(UI.secondary)
                                }
                                Text(item.title)
                                    .font(UI.font(28, .semibold))
                                    .foregroundStyle(UI.text)
                                if !item.description.isEmpty {
                                    Text(item.description)
                                        .font(UI.font(22))
                                        .foregroundStyle(UI.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, UI.s(8))
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
