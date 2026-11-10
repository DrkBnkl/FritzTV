import SwiftUI
import AppKit

/// Erzwingt auf dem Mac ein festes Seitenverhältnis (z. B. 16:9 für TV-Bild) und eine Mindestgröße
/// für das Hauptfenster beim Vergrößern und Verkleinern mit der Maus.
struct WindowAspectRatioModifier: ViewModifier {
    let aspectRatio: NSSize
    let minSize: NSSize

    func body(content: Content) -> some View {
        content
            .background(WindowConfiguratorRepresentable(aspectRatio: aspectRatio, minSize: minSize))
    }
}

private struct WindowConfiguratorRepresentable: NSViewRepresentable {
    let aspectRatio: NSSize
    let minSize: NSSize

    func makeNSView(context: Context) -> WindowConfiguratorView {
        let view = WindowConfiguratorView()
        view.targetAspectRatio = aspectRatio
        view.targetMinSize = minSize
        return view
    }

    func updateNSView(_ nsView: WindowConfiguratorView, context: Context) {
        nsView.targetAspectRatio = aspectRatio
        nsView.targetMinSize = minSize
        nsView.applyConfiguration()
    }
}

private final class WindowConfiguratorView: NSView {
    var targetAspectRatio: NSSize = NSSize(width: 16, height: 9)
    var targetMinSize: NSSize = NSSize(width: 640, height: 360)

    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        if let window {
            // Die Fensterwiederherstellung setzt den Rahmen nach dem Einhängen der Ansicht
            // und ohne Rücksicht auf `aspectRatio` (z. B. 640 × 392 aus älteren Versionen).
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, !window.inLiveResize else { return }
                    self.correctFrameIfNeeded(window)
                }
            }
        }
        applyConfiguration()
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    /// Seitenverhältnis und Mindestgröße gelten für den gesamten Fensterrahmen, nicht für den
    /// Inhaltsbereich: Bei ausgeblendeter Titelleiste reicht das Bild bis an den oberen Rand, der
    /// Inhaltsbereich zählt die Titelleiste aber nicht mit. Mit `contentAspectRatio` wurde das Fenster
    /// beim Ziehen deshalb um die Titelleistenhöhe (rund 32 pt) zu hoch, und das Bild bekam Balken.
    func applyConfiguration() {
        guard let window else { return }
        if window.aspectRatio != targetAspectRatio {
            window.aspectRatio = targetAspectRatio
        }
        if window.minSize != targetMinSize {
            window.minSize = targetMinSize
        }
        if !window.inLiveResize { correctFrameIfNeeded(window) }
    }

    /// Bringt ein Fenster mit abweichendem Seitenverhältnis (z. B. aus einer früheren Version
    /// gespeichert) einmalig auf das Zielformat; die linke obere Ecke bleibt stehen.
    private func correctFrameIfNeeded(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen), targetAspectRatio.width > 0 else { return }
        var frame = window.frame
        let height = (frame.width * targetAspectRatio.height / targetAspectRatio.width).rounded()
        guard abs(frame.height - height) >= 1 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }
}
