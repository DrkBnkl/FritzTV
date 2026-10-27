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
        player.drawable = view.videoView
        return view
    }

    func updateUIView(_ uiView: VideoHostView, context: Context) {
        if (player.drawable as? UIView) != uiView.videoView {
            player.drawable = uiView.videoView
        }
        uiView.previewFrame = previewFrame
    }
}

/// Behälter für die VLC-Zeichenfläche. Verkleinern und Verschieben für die Programmübersicht
/// geschieht per UIKit-Transformation an der inneren Fläche `videoView`; der Behälter selbst,
/// den SwiftUI verwaltet, bleibt unverändert. (SwiftUI-Effekte direkt an der eingebetteten
/// Ansicht bzw. eine Transformation am Behälter führten zu stehendem Bild bzw. Abstürzen.)
final class VideoHostView: UIView {
    let videoView = UIView()

    var previewFrame: CGRect? {
        didSet { if previewFrame != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        videoView.backgroundColor = .black
        addSubview(videoView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Größe immer bildschirmfüllend, nur über bounds/center (nie frame, solange transformiert).
        videoView.bounds = CGRect(origin: .zero, size: bounds.size)
        videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)

        guard let target = previewFrame, target.width >= 10, target.height >= 10,
              target.minX.isFinite, target.minY.isFinite,
              bounds.width > 0, bounds.height > 0, window != nil else {
            videoView.transform = .identity
            videoView.layer.cornerRadius = 0
            videoView.layer.masksToBounds = false
            return
        }
        let scale = target.width / bounds.width
        let targetCenter = convert(CGPoint(x: target.midX, y: target.midY), from: nil)
        videoView.transform = CGAffineTransform(translationX: targetCenter.x - bounds.midX,
                                                y: targetCenter.y - bounds.midY)
            .scaledBy(x: scale, y: scale)
        videoView.layer.cornerRadius = 10 / scale
        videoView.layer.masksToBounds = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DebugLog.log("Bildfläche \(window == nil ? "aus dem Fenster genommen" : "im Fenster")")
        setNeedsLayout()
    }
}
#endif
