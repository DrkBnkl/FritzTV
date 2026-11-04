import AppKit
import Combine
import SwiftUI
import FritzTVKit

/// FritzRadio: Radio vom Kabelanschluss der FRITZ!Box, nur als Symbol in der Menüleiste.
/// Kein Dock-Symbol (`LSUIElement`), kein eigenes Fenster. Beim Öffnen aus dem Finder oder Launchpad
/// klappt das Panel unter dem Symbol auf, damit man sieht, dass die App läuft.
///
/// Eigenes `NSStatusItem` statt `MenuBarExtra`: Nur so lässt sich das Panel auch per Programm öffnen.
@main
struct FritzRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Szene nur als Träger der Tastaturbefehle; ⌘, ist ersetzt, ein Einstellungsfenster gibt es nicht.
        Settings { EmptyView() }
            .commands {
                RadioCommands(model: appDelegate.model)
            }
    }
}

/// Tastaturbefehle im Panel. Die Menüleiste der App ist ausgeblendet, die Kurzbefehle gelten trotzdem.
private struct RadioCommands: Commands {
    @ObservedObject var model: RadioModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen …") { model.showsSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .textEditing) {
            Button("Sender suchen") { model.focusSearch() }
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
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = RadioModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusSymbol = ""
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        installSpaceKey()

        // Beim Start als Anmeldeobjekt bleibt das Panel zu.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin {
            // Das Symbol braucht einen Moment, bis es in der Menüleiste steht.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() }
        }
    }

    /// Erneutes Öffnen, während FritzRadio schon läuft (Finder, Launchpad).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // MARK: Menüleistensymbol

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "FritzRadio"
        statusItem = item
        updateStatusIcon()
        // Gefülltes Symbol, solange Radio läuft.
        model.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.updateStatusIcon() } }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        let name = model.isPlaying ? "radio.fill" : "radio"
        guard name != statusSymbol else { return }
        statusSymbol = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "FritzRadio")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func togglePanel() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button, button.window != nil else { return }
        let popover = self.popover ?? makePopover()
        self.popover = popover
        guard !popover.isShown else { return }
        // Aktiv, damit Suchfeld und Tastaturbefehle sofort ansprechen.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: RadioPanel(model: model))
        return popover
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
}
