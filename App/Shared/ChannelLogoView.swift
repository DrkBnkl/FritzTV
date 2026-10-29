import SwiftUI
import FritzTVKit

/// Zeigt das Senderlogo vom AVM-Server. Probiert die möglichen Dateinamen der Reihe nach
/// und blendet sich aus, wenn keiner passt. Geladene Bilder hält der URLCache der App.
struct ChannelLogoView: View {
    let channelName: String
    var height: CGFloat = 36
    var maxWidth: CGFloat = 80

    @State private var attempt = 0

    var body: some View {
        // Group, damit `onChange` auch greift, wenn gerade kein Bild angezeigt wird.
        Group { logo }
            // Dieselbe Ansicht zeigt nacheinander verschiedene Sender (Infoleiste beim Umschalten):
            // Ohne Zurücksetzen bliebe nach einem Sender ohne Logo jedes weitere Logo aus.
            .onChange(of: channelName) { _, _ in attempt = 0 }
    }

    @ViewBuilder private var logo: some View {
        let urls = ChannelLogo.candidateURLs(for: channelName)
        if attempt < urls.count {
            AsyncImage(url: urls[attempt]) { phase in
                switch phase {
                case .success(let image):
                    let cornerRadius = max(UI.s(6), 4)
                    let hPadding = max(UI.s(6), 4)
                    let vPadding = max(UI.s(3), 2)
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, hPadding)
                        .padding(.vertical, vPadding)
                        .frame(maxHeight: height)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .frame(maxWidth: maxWidth, maxHeight: height)
                case .failure:
                    Color.clear.frame(width: 0, height: height)
                        .onAppear { attempt += 1 }
                default:
                    Color.clear.frame(width: 0, height: height)
                }
            }
            .id(urls[attempt])
        }
    }
}
