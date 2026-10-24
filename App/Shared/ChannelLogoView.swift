import SwiftUI
import FritzTVKit

/// Zeigt das Senderlogo vom AVM-Server für einen Sender an.
struct ChannelLogoView: View {
    let channelName: String
    var height: CGFloat = 36
    var maxWidth: CGFloat = 80

    var body: some View {
        if let url = ChannelLogo.url(for: channelName) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: maxWidth, maxHeight: height)
                default:
                    Color.clear.frame(width: 0, height: height)
                }
            }
        }
    }
}
