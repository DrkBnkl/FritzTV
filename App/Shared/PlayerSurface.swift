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

/// Behälter für die VLC-Zeichenfläche. Für die Programmübersicht bekommt die innere Fläche
/// `videoView` den Rahmen des Vorschaufensters; der Behälter selbst, den SwiftUI verwaltet,
/// bleibt unverändert. (SwiftUI-Effekte direkt an der eingebetteten Ansicht bzw. eine
/// Transformation am Behälter führten zu Abstürzen.)
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
        // Vorschau: Die VLC-Fläche bekommt wirklich die kleine Größe (kein Skalieren per
        // Transformation, keine Maske). Auf dem Apple TV hielt das skalierte, abgerundete
        // Vollbild-Video den Hauptthread pro Bild auf – die Übersicht reagierte nur zäh.
        var target = bounds
        if let preview = previewFrame, preview.width >= 10, preview.height >= 10,
           preview.minX.isFinite, preview.minY.isFinite, window != nil {
            target = convert(preview, from: nil)
        }
        if videoView.transform != .identity { videoView.transform = .identity }
        if videoView.frame != target { videoView.frame = target }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DebugLog.log("Bildfläche \(window == nil ? "aus dem Fenster genommen" : "im Fenster")")
        setNeedsLayout()
    }
}
#endif
