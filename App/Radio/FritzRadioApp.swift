import AppKit
import Combine
import SwiftUI
import FritzTVKit

/// FritzRadio: Radio vom Kabelanschluss der FRITZ!Box, als Symbol in der Menüleiste.
/// Kein Dock-Symbol (`LSUIElement`). Beim Öffnen aus dem Finder oder Launchpad erscheint zusätzlich
/// ein Fenster: Ist das Menüleistensymbol ausgeblendet (volle Menüleiste, Kamera-Aussparung,
/// Systemeinstellungen › Menüleiste), wäre die App sonst nicht zu bedienen. Solange das Fenster
/// offen ist, verhält sich FritzRadio wie eine normale App: Dock-Symbol, ⌘-Tab und Menüleiste.
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
        .commands {
            RadioCommands(model: appDelegate.model, showWindow: appDelegate.showWindow)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: RadioModel

    var body: some View {
        Image(systemName: model.isPlaying ? "radio.fill" : "radio")
    }
}

/// Menüs, solange das Fenster offen ist; die Kurzbefehle gelten auch im Menüleistenfenster.
private struct RadioCommands: Commands {
    @ObservedObject var model: RadioModel
    let showWindow: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen …") {
                showWindow()
                model.showsSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .textEditing) {
            Button("Sender suchen") {
                showWindow()
                model.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Wiedergabe") {
            Button(model.isPlaying ? "Anhalten" : "Abspielen") { model.togglePlayback() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(model.loadState != .ready)
            Divider()
            Button("Nächster Sender") { model.step(+1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(model.current == nil)
            Button("Voriger Sender") { model.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(model.current == nil)
            Divider()
            Button("Lauter") { model.changeVolume(by: 10) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Leiser") { model.changeVolume(by: -10) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            if let current = model.current {
                Button(model.isFavorite(current) ? "Aus den Favoriten entfernen" : "Zu den Favoriten") {
                    model.toggleFavorite(current)
                }
                .keyboardShortcut("d", modifiers: .command)
            }
            let favorites = model.favorites.prefix(9)
            if !favorites.isEmpty {
                Divider()
                ForEach(Array(favorites.enumerated()), id: \.element.key) { index, station in
                    Button(station.displayName) { model.play(station) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            Divider()
            Button("Senderliste neu laden") { Task { await model.load() } }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(before: .windowList) {
            Button("FritzRadio-Fenster") { showWindow() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = RadioModel()
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSpaceKey()
        // Fenstertitel zeigt den laufenden Sender, z. B. für ⌘-Tab und Mission Control.
        model.$current
            .sink { [weak self] station in self?.window?.subtitle = station?.displayName ?? "" }
            .store(in: &cancellables)

        // Beim Start als Anmeldeobjekt bleibt es beim Menüleistensymbol.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin { showWindow() }
    }

    /// Erneutes Öffnen, während FritzRadio schon läuft (Finder, Launchpad, Klick aufs Dock-Symbol).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// Fenster zu heißt nicht Radio aus: Der Ton läuft über das Menüleistensymbol weiter.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: RadioPanel(model: model, isWindow: true))
            // Die Größe bestimmt der Benutzer; SwiftUI liefert nur die Mindestgröße.
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "FritzRadio"
            window.subtitle = model.current?.displayName ?? ""
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 380, height: 640))
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            window.setFrameAutosaveName(Self.frameName)
            self.window = window
        }
        // Mit offenem Fenster als normale App: Dock-Symbol, ⌘-Tab und Menüleiste mit den Befehlen.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Leertaste startet bzw. stoppt das Radio, außer beim Tippen (Suchfeld, Adresse).
    private func installSpaceKey() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(event.window?.firstResponder is NSText),
                  model.loadState == .ready else { return event }
            model.togglePlayback()
            return nil
        }
    }

    private static let frameName = "FritzRadioWindow"
}
