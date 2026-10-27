import SwiftUI
import VLCKitSPM
#if canImport(TVVLCKit)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif

/// Fläche, in die VLCKit das Bild zeichnet.
#if os(macOS)
struct PlayerSurface: NSViewRepresentable {
    let player: VLCMediaPlayer
    /// Nur Apple TV; auf dem Mac verkleinert `EPGPreviewPlacement`.
    var previewFrame: CGRect? = nil

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        player.drawable = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if (player.drawable as? NSView) != nsView {
            player.drawable = nsView
        }
    }
}
#else
struct PlayerSurface: UIViewRepresentable {
    let player: VLCMediaPlayer
    /// Vorschaufenster der Programmübersicht (Bildschirmkoordinaten) oder `nil` für Vollbild.
    var previewFrame: CGRect? = nil

    func makeUIView(context: Context) -> VideoHostView {
        let view = VideoHostView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: VideoHostView, context: Context) {
        if (player.drawable as? UIView) != uiView {
            player.drawable = uiView
        }
        uiView.previewFrame = previewFrame
    }
}

/// Zeichenfläche für VLC. Verkleinern und Verschieben für die Programmübersicht geschieht hier
/// per UIKit-Transformation, nicht über SwiftUI-Modifier: Ändert SwiftUI Effekte wie
/// Zuschnitt oder Skalierung an der eingebetteten Ansicht, hängt es sie intern um – VLC
/// zeichnet dann weiter in die alte Fläche und das Bild bleibt stehen (auch nach dem Zurückkehren).
final class VideoHostView: UIView {
    var previewFrame: CGRect? {
        didSet { if previewFrame != oldValue { applyPreview() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPreview()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DebugLog.log("Bildfläche \(window == nil ? "aus dem Fenster genommen" : "im Fenster")")
    }

    private func applyPreview() {
        guard let target = previewFrame, bounds.width > 0, bounds.height > 0, let superview else {
            transform = .identity
            layer.cornerRadius = 0
            layer.masksToBounds = false
            return
        }
        let scale = target.width / bounds.width
        // Mittelpunkt dieser Fläche in Bildschirmkoordinaten (ohne Transformation).
        let center = superview.convert(self.center, to: nil)
        transform = CGAffineTransform(translationX: target.midX - center.x, y: target.midY - center.y)
            .scaledBy(x: scale, y: scale)
        layer.cornerRadius = 10 / max(scale, 0.01)
        layer.masksToBounds = true
    }
}
#endif
