import AppKit
import SwiftUI

/// FritzRadio: Radio vom Kabelanschluss der FRITZ!Box, als Symbol in der Menüleiste.
/// Kein Dock-Symbol (`LSUIElement`). Beim Öffnen aus dem Finder oder Launchpad erscheint zusätzlich
/// ein Fenster: Ist das Menüleistensymbol ausgeblendet (volle Menüleiste, Kamera-Aussparung,
/// Systemeinstellungen › Menüleiste), wäre die App sonst nicht zu bedienen.
@main
struct FritzRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            RadioPanel(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: RadioModel

    var body: some View {
        Image(systemName: model.isPlaying ? "radio.fill" : "radio")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = RadioModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Beim Start als Anmeldeobjekt bleibt es beim Menüleistensymbol.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin { showWindow() }
    }

    /// Erneutes Öffnen, während FritzRadio schon läuft.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: RadioPanel(model: model)))
            window.title = "FritzRadio"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
