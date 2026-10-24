import SwiftUI
import AppKit

/// Mac-Tastatur statt Siri Remote:
/// ↑/↓ = Sender, Return = Klick, Esc = Zurück, Leertaste = Play/Pause, ←/→ = 10 s, Ziffern = Direktwahl.
struct RemoteInputModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool
    @State private var keyMonitor: Any?

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear {
                focused = true
                setupKeyMonitor()
            }
            .onDisappear {
                if let keyMonitor {
                    NSEvent.removeMonitor(keyMonitor)
                    self.keyMonitor = nil
                }
            }
            .onChange(of: model.showSettings) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.showMediathek) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.showEPGOverview) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.activeHLSReplay != nil) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.activeMediathekURL != nil) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.searchResultDialog != nil) { _, showing in
                if !showing { focused = true }
            }
    }

    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Befehle mit Cmd-Taste (z. B. Cmd+, für Einstellungen oder Cmd+Q für Beenden) unverändert durchlassen
            if event.modifierFlags.contains(.command) {
                return event
            }

            // Wenn der Mediathek-Suchdialog aktiv ist: Tastensteuerung für Navigation und Auswahl
            if model.searchResultDialog != nil {
                if event.keyCode == 53 { // Escape
                    model.searchResultDialog = nil
                    return nil
                }
                if event.keyCode == 126 { // Up Arrow
                    NotificationCenter.default.post(name: .searchResultMove, object: -1)
                    return nil
                }
                if event.keyCode == 125 { // Down Arrow
                    NotificationCenter.default.post(name: .searchResultMove, object: 1)
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
                    NotificationCenter.default.post(name: .searchResultSelect, object: nil)
                    return nil
                }
                return event
            }

            // Wenn Mediathek-Wiedergabe aktiv ist: Tasten für Steuerung nutzen (Zurück, Spulen, Pause)
            if model.activeMediathekURL != nil {
                if event.keyCode == 53 || event.keyCode == 51 { // Escape oder Backspace
                    model.mediathekPlayClosed()
                    return nil
                }
                if event.keyCode == 123 { // Left Arrow: Spulen zurück (progressiv)
                    NotificationCenter.default.post(name: .mediathekJump, object: false)
                    return nil
                }
                if event.keyCode == 124 { // Right Arrow: Spulen vor (progressiv)
                    NotificationCenter.default.post(name: .mediathekJump, object: true)
                    return nil
                }
                if event.keyCode == 49 { // Space: Play/Pause
                    NotificationCenter.default.post(name: .mediathekTogglePause, object: nil)
                    return nil
                }
                if event.keyCode == 125 || event.keyCode == 126 { // Up/Down: interne Lautstärkeeinblendung verhindern
                    return nil
                }
                return event
            }

            // Wenn Replay aktiv ist, Tasten für Steuerung nutzen (Zurück, Spulen, Pause)
            if model.activeHLSReplay != nil {
                if event.keyCode == 53 || event.keyCode == 51 { // Escape oder Backspace
                    model.hlsReplayClosed()
                    return nil
                }
                if event.keyCode == 123 { // Left Arrow: Spulen zurück (progressiv)
                    NotificationCenter.default.post(name: .hlsReplayJump, object: false)
                    return nil
                }
                if event.keyCode == 124 { // Right Arrow: Spulen vor (progressiv)
                    NotificationCenter.default.post(name: .hlsReplayJump, object: true)
                    return nil
                }
                if event.keyCode == 49 { // Space: Play/Pause
                    NotificationCenter.default.post(name: .hlsReplayTogglePause, object: nil)
                    return nil
                }
                if event.keyCode == 125 || event.keyCode == 126 { // Up/Down: interne Lautstärkeeinblendung verhindern
                    return nil
                }
                return event
            }

            // Wenn ein Sheet aktiv ist (z. B. Einstellungen, Mediathek, EPG), dem Sheet die Tasten überlassen
            if model.showSettings || model.showMediathek || model.showEPGOverview {
                return event
            }

            switch event.keyCode {
            case 126: // Up Arrow
                model.handle(.up)
                return nil
            case 125: // Down Arrow
                model.handle(.down)
                return nil
            case 123: // Left Arrow
                model.handle(.left)
                return nil
            case 124: // Right Arrow
                model.handle(.right)
                return nil
            case 36, 76: // Return / Enter
                model.handle(.select)
                return nil
            case 53: // Escape
                model.handle(.back)
                return nil
            case 49: // Space
                model.handle(.playPause)
                return nil
            default:
                if let chars = event.characters, let digit = Int(chars) {
                    model.handle(.digit(digit))
                    return nil
                }
                return event
            }
        }
    }
}
