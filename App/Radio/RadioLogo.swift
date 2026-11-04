import AppKit
import SwiftUI
import FritzTVKit

/// Geladene Radiologos. Beim Blättern erscheinen dieselben Zeilen immer wieder; ohne eigenen Speicher
/// würde jedes Logo dabei kurz verschwinden und neu laden.
@MainActor
final class RadioLogoCache {
    static let shared = RadioLogoCache()
    private var images: [String: NSImage] = [:]
    private var missing: Set<String> = []

    func image(for name: String) -> NSImage? { images[name] }

    func load(_ name: String) async -> NSImage? {
        if let image = images[name] { return image }
        guard !missing.contains(name) else { return nil }
        for url in ChannelLogo.radioCandidateURLs(for: name) {
            guard let (data, response) = try? await URLSession.shared.data(from: url) else {
                if Task.isCancelled { return nil }
                continue
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { continue }
            images[name] = image
            return image
        }
        if !Task.isCancelled { missing.insert(name) }
        return nil
    }
}

/// Senderlogo oder, solange keines da ist, eine Kachel mit dem Sendernamen in der Farbe der
/// Senderfamilie. So bleibt nie eine Lücke, auch für Sender, zu denen es kein Logo gibt.
struct RadioLogoView: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    /// Meldet ein frisch geladenes Logo, z. B. für die Anzeige im Kontrollzentrum.
    var onLoad: (() -> Void)? = nil

    @State private var image: NSImage?

    var body: some View {
        let corner = max(height * 0.14, 3)
        ZStack {
            if let image {
                RoundedRectangle(cornerRadius: corner).fill(Color.white)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: corner))
            } else {
                RoundedRectangle(cornerRadius: corner).fill(Self.tileColor(for: name))
                Text(name)
                    .font(.system(size: height * 0.3, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .padding(height * 0.08)
            }
        }
        .frame(width: width, height: height)
        .task(id: name) {
            image = RadioLogoCache.shared.image(for: name)
            guard image == nil else { return }
            let loaded = await RadioLogoCache.shared.load(name)
            guard !Task.isCancelled else { return }
            image = loaded
            if loaded != nil { onLoad?() }
        }
    }

    /// Feste Farbe je Senderfamilie.
    private static func tileColor(for name: String) -> Color {
        let family = RadioStations.familyTitle(of: name)
        let hue = family.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31 &+ $1.value) % 360 }
        return Color(hue: Double(hue) / 360, saturation: 0.55, brightness: 0.45)
    }
}
