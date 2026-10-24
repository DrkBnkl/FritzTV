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
        let urls = ChannelLogo.candidateURLs(for: channelName)
        if attempt < urls.count {
            AsyncImage(url: urls[attempt]) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
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
