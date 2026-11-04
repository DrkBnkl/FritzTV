import SwiftUI

/// FritzRadio: Radio vom Kabelanschluss der FRITZ!Box, als Symbol in der Menüleiste.
/// Kein Fenster und kein Dock-Symbol (`LSUIElement`).
@main
struct FritzRadioApp: App {
    @StateObject private var model = RadioModel()

    var body: some Scene {
        MenuBarExtra {
            RadioPanel(model: model)
        } label: {
            Image(systemName: model.isPlaying ? "radio.fill" : "radio")
        }
        .menuBarExtraStyle(.window)
    }
}
