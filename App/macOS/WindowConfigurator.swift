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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    func applyConfiguration() {
        guard let window else { return }
        if window.contentAspectRatio != targetAspectRatio {
            window.contentAspectRatio = targetAspectRatio
        }
        if window.contentMinSize != targetMinSize {
            window.contentMinSize = targetMinSize
        }
    }
}
