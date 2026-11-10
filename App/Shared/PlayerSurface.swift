import SwiftUI
import FritzTVKit
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
import AppKit

extension NSImage {
    /// Erzeugt ein quadratisches Miniaturbild mit exakt beibehaltenem Seitenverhältnis des Videos
    /// und abgerundeten Ecken, damit das Dock-Icon die 16:9-Wiedergabe nicht auf ein 1:1-Quadrat verzerrt.
    func aspectFittedForDock(size targetSize: CGFloat = 256) -> NSImage {
        let rep = representations.first
        let pixelWidth = CGFloat(rep?.pixelsWide ?? Int(size.width))
        let pixelHeight = CGFloat(rep?.pixelsHigh ?? Int(size.height))
        guard pixelWidth > 0, pixelHeight > 0 else { return self }

        let aspect = pixelWidth / pixelHeight
        var drawWidth = targetSize
        var drawHeight = targetSize
        if aspect > 1.0 { // Breiter als hoch (z. B. 16:9)
            drawHeight = (targetSize / aspect).rounded()
        } else { // Höher als breit oder 1:1
            drawWidth = (targetSize * aspect).rounded()
        }

        let drawRect = NSRect(
            x: ((targetSize - drawWidth) / 2.0).rounded(),
            y: ((targetSize - drawHeight) / 2.0).rounded(),
            width: drawWidth,
            height: drawHeight
        )

        let canvas = NSImage(size: NSSize(width: targetSize, height: targetSize))
        canvas.lockFocus()

        let cornerRadius: CGFloat = 12.0
        let clipPath = NSBezierPath(roundedRect: drawRect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()
        draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // Subtiler Rahmen für saubere Abgrenzung im Dock
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let strokePath = NSBezierPath(roundedRect: drawRect.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        strokePath.lineWidth = 1.0
        strokePath.stroke()

        canvas.unlockFocus()
        return canvas
    }

    /// Überblendet zwei Dock-Bilder für einen sanften, ablenkungsfreien Übergang im Dock.
    func crossfaded(with other: NSImage, progress: CGFloat) -> NSImage {
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        draw(in: NSRect(origin: .zero, size: size),
             from: .zero,
             operation: .sourceOver,
             fraction: 1.0 - progress)
        other.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: progress)
        canvas.unlockFocus()
        return canvas
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: VLCMediaPlayer
    /// Nur Apple TV; auf dem Mac verkleinert `EPGPreviewPlacement`.
    var previewFrame: CGRect? = nil
    var dockLivePreview: Bool = true
    /// Vergrößerung der VLC-Fläche (Overscan bei SD, `PictureCrop`); der Rand wird abgeschnitten.
    var zoom: PictureCrop.Zoom = .none

    func makeNSView(context: Context) -> MacVideoHostView {
        let view = MacVideoHostView()
        view.player = player
        view.dockLivePreview = dockLivePreview
        view.zoom = zoom
        bindDrawable(view.videoView)
        return view
    }

    func updateNSView(_ nsView: MacVideoHostView, context: Context) {
        nsView.player = player
        nsView.dockLivePreview = dockLivePreview
        nsView.zoom = zoom
        if (player.drawable as? NSView) != nsView.videoView {
            bindDrawable(nsView.videoView)
        }
    }

    private func bindDrawable(_ videoView: NSView) {
        let wasPlaying = player.isPlaying
        player.drawable = videoView
        // VLCKit bindet seine Videoausgabe (vout) unter macOS nur beim Start der Wiedergabe
        // an `drawable`. Wird ein neues Fenster geöffnet, während der Player noch läuft,
        // muss die Wiedergabe kurz neu angestoßen werden, damit das Bild nicht schwarz bleibt.
        if wasPlaying {
            player.stop()
            player.play()
        }
    }
}

/// Behälter für die VLC-Zeichenfläche auf dem Mac.
/// Zeigt im minimierten Dock-Fenster ein Standbild (Screenshot) des laufenden Programms an.
/// Die Videofläche wird während der Minimierung ausgeblendet, sodass keine OpenGL-Frames
/// gerendert werden (kein Ruckeln, 0 % GPU-Last).
final class MacVideoHostView: NSView {
    weak var player: VLCMediaPlayer?
    var dockLivePreview: Bool = true
    var zoom: PictureCrop.Zoom = .none {
        didSet { if zoom != oldValue { needsLayout = true } }
    }
    let videoView = NSView()
    private var windowObservers: [NSObjectProtocol] = []
    private var snapshotTimer: Timer?
    private var crossfadeTimer: Timer?
    private var lastSnapshotImage: NSImage?
    private var snapshotPath: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fritztv_dock_snapshot.png")
            .path
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // Die VLC-Fläche kann größer sein als der Behälter (Overscan); der Rand wird abgeschnitten.
        layer?.masksToBounds = true
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.black.cgColor
        videoView.frame = bounds
        addSubview(videoView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    override func layout() {
        super.layout()
        let target = zoom.frame(in: bounds)
        if videoView.frame != target {
            videoView.frame = target
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        stopSnapshotTimer()
        guard let window else { return }
        window.miniwindowImage = nil
        window.dockTile.contentView = nil
        window.dockTile.display()

        let nc = NotificationCenter.default
        windowObservers.append(
            nc.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleWillMiniaturize()
            }
        )
        windowObservers.append(
            nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleDidMiniaturize()
            }
        )
        windowObservers.append(
            nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleDidDeminiaturize()
            }
        )
        windowObservers.append(
            nc.addObserver(forName: Notification.Name("VLCMediaPlayerSnapshotTaken"), object: nil, queue: .main) { [weak self] notif in
                self?.handleSnapshotTaken(notif)
            }
        )

        startSnapshotTimer()
    }

    private func startSnapshotTimer() {
        stopSnapshotTimer()
        // Nach Wiedergabebeginn zeitnah erstes Standbild sichern
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, let player = self.player, player.isPlaying, player.hasVideoOut else { return }
            self.takeSnapshot()
        }
        // Regelmäßig im Hintergrund ein aktuelles Standbild für das Dock-Icon vorhalten.
        // Intervall: 12 Sekunden (angenehm ruhig, kein nerviges Stroboskop/Flimmern im Augenwinkel).
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, player.isPlaying, player.hasVideoOut else { return }
            // Wenn das Fenster minimiert ist und die Dock-Vorschau deaktiviert wurde,
            // bleibt das Standbild stehen und es werden keine neuen Snapshots angefordert.
            if let window = self.window, window.isMiniaturized, !self.dockLivePreview {
                return
            }
            self.takeSnapshot()
        }
    }

    private func stopSnapshotTimer() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    private func takeSnapshot() {
        guard let player, player.isPlaying, player.hasVideoOut, player.videoSize.width > 0 else { return }
        try? FileManager.default.removeItem(atPath: snapshotPath)
        let path = snapshotPath
        _ = SafeObjCExecute {
            player.saveVideoSnapshot(at: path, withWidth: 320, andHeight: 0)
        }
    }

    private func ensureDockImageView() -> NSImageView? {
        guard let window else { return nil }
        if let iv = window.dockTile.contentView as? NSImageView {
            return iv
        }
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        iv.imageScaling = .scaleProportionallyUpOrDown
        window.dockTile.contentView = iv
        return iv
    }

    private func applyDockImage(_ image: NSImage) {
        guard let window else { return }
        window.miniwindowImage = image
        if let iv = ensureDockImageView() {
            iv.image = image
            window.dockTile.display()
        }
    }

    private func transitionToDockImage(_ newImage: NSImage) {
        guard let window, window.isMiniaturized else {
            lastSnapshotImage = newImage
            applyDockImage(newImage)
            return
        }

        crossfadeTimer?.invalidate()

        guard let fromImage = lastSnapshotImage else {
            lastSnapshotImage = newImage
            applyDockImage(newImage)
            return
        }

        // Sanfter Übergang: 10 Schritte à 80 ms = 800 ms Gesamtdauer.
        // Keine harten Sprünge, kein Flackern im Augenwinkel.
        let steps = 10
        let stepDuration = 0.08
        var currentStep = 0

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self, let win = self.window, win.isMiniaturized else {
                timer.invalidate()
                return
            }
            currentStep += 1
            let progress = min(1.0, CGFloat(currentStep) / CGFloat(steps))
            let blended = fromImage.crossfaded(with: newImage, progress: progress)
            self.applyDockImage(blended)

            if currentStep >= steps {
                timer.invalidate()
                self.crossfadeTimer = nil
                self.lastSnapshotImage = newImage
            }
        }
    }

    private func handleWillMiniaturize() {
        guard let window else { return }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        // Sobald das Fenster beginnt, ins Dock zu gleiten: sofort das aktuellste Standbild setzen
        if let image = lastSnapshotImage {
            applyDockImage(image)
        } else if let last = player?.lastSnapshot {
            let fitted = last.aspectFittedForDock()
            lastSnapshotImage = fitted
            applyDockImage(fitted)
        }
        takeSnapshot()
    }

    private func handleSnapshotTaken(_ notif: Notification) {
        if let notifPlayer = notif.object as? VLCMediaPlayer, let player, notifPlayer !== player {
            return
        }
        let rawImage: NSImage?
        if let last = player?.lastSnapshot {
            rawImage = last
        } else if FileManager.default.fileExists(atPath: snapshotPath),
                  let fileImage = NSImage(contentsOfFile: snapshotPath) {
            rawImage = fileImage
        } else {
            rawImage = nil
        }
        guard let rawImage else { return }
        let fitted = rawImage.aspectFittedForDock()
        if let window, window.isMiniaturized {
            if dockLivePreview {
                transitionToDockImage(fitted)
            }
        } else {
            lastSnapshotImage = fitted
        }
    }

    private func handleDidMiniaturize() {
        // Sicherstellen, dass das Standbild im Dock-Icon angezeigt wird
        if let window, window.miniwindowImage == nil {
            if let image = lastSnapshotImage {
                applyDockImage(image)
            } else if let rawImage = player?.lastSnapshot ?? (
                FileManager.default.fileExists(atPath: snapshotPath) ? NSImage(contentsOfFile: snapshotPath) : nil
            ) {
                let fitted = rawImage.aspectFittedForDock()
                lastSnapshotImage = fitted
                applyDockImage(fitted)
            }
        }
        // Videofläche ausblenden, damit keine OpenGL-Frames mehr ins Dock gerendert werden (kein Ruckeln, 0 % GPU-Last)
        videoView.isHidden = true
    }

    private func handleDidDeminiaturize() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        videoView.isHidden = false
        window?.miniwindowImage = nil
        if let window {
            window.dockTile.contentView = nil
            window.dockTile.display()
        }
        videoView.frame = zoom.frame(in: bounds)
        videoView.needsLayout = true
        videoView.needsDisplay = true
        videoView.layer?.setNeedsDisplay()
        for subview in videoView.subviews {
            subview.frame = videoView.bounds
            subview.needsLayout = true
            subview.needsDisplay = true
            subview.layer?.setNeedsDisplay()
        }
        // Nach dem Wiederherstellen direkt ein frisches Standbild für das nächste Minimieren anfordern
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.takeSnapshot()
        }
    }

    private func removeObservers() {
        for obs in windowObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        windowObservers.removeAll()
    }

    deinit {
        stopSnapshotTimer()
        removeObservers()
        try? FileManager.default.removeItem(atPath: snapshotPath)
    }
}
#else
struct PlayerSurface: UIViewRepresentable {
    let player: VLCMediaPlayer
    /// Vorschaufenster der Programmübersicht (Bildschirmkoordinaten) oder `nil` für Vollbild.
    var previewFrame: CGRect? = nil
    var dockLivePreview: Bool = true
    /// Vergrößerung der VLC-Fläche (Overscan bei SD, `PictureCrop`); der Rand wird abgeschnitten.
    var zoom: PictureCrop.Zoom = .none

    func makeUIView(context: Context) -> VideoHostView {
        let view = VideoHostView()
        view.zoom = zoom
        player.drawable = view.videoView
        return view
    }

    func updateUIView(_ uiView: VideoHostView, context: Context) {
        if (player.drawable as? UIView) != uiView.videoView {
            player.drawable = uiView.videoView
        }
        uiView.previewFrame = previewFrame
        uiView.zoom = zoom
    }
}

/// Behälter für die VLC-Zeichenfläche. Für die Programmübersicht bekommt die innere Fläche
/// `videoView` den Rahmen des Vorschaufensters; der Behälter selbst, den SwiftUI verwaltet,
/// bleibt unverändert. (SwiftUI-Effekte direkt an der eingebetteten Ansicht bzw. eine
/// Transformation am Behälter führten zu Abstürzen.)
final class VideoHostView: UIView {
    let videoView = UIView()
    /// Rechteckiger Ausschnitt um die VLC-Fläche: Bei Overscan ist sie größer als der Bildbereich.
    private let clipView = UIView()

    var previewFrame: CGRect? {
        didSet { if previewFrame != oldValue { setNeedsLayout() } }
    }

    var zoom: PictureCrop.Zoom = .none {
        didSet { if zoom != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipView.backgroundColor = .black
        clipView.clipsToBounds = true
        videoView.backgroundColor = .black
        clipView.addSubview(videoView)
        addSubview(clipView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Vorschau: Die VLC-Fläche bekommt wirklich die kleine Größe (kein Skalieren per
        // Transformation, keine abgerundete Maske). Auf dem Apple TV hielt das skalierte, abgerundete
        // Vollbild-Video den Hauptthread pro Bild auf – die Übersicht reagierte nur zäh.
        var target = bounds
        if let preview = previewFrame, preview.width >= 10, preview.height >= 10,
           preview.minX.isFinite, preview.minY.isFinite, window != nil {
            target = convert(preview, from: nil)
        }
        if videoView.transform != .identity { videoView.transform = .identity }
        if clipView.frame != target { clipView.frame = target }
        let videoFrame = zoom.frame(in: clipView.bounds)
        if videoView.frame != videoFrame { videoView.frame = videoFrame }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DebugLog.log("Bildfläche \(window == nil ? "aus dem Fenster genommen" : "im Fenster")")
        setNeedsLayout()
    }
}
#endif
