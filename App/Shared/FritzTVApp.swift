import SwiftUI
#if os(macOS)
import AppKit

/// Beendet die Mac-App vollständig, sobald das Hauptfenster über den roten Schließen-Knopf
/// geschlossen wird, statt ohne Fenster mit laufendem Ton im Dock weiterzulaufen.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main
struct FritzTVApp: App {
    @StateObject private var model = AppModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    init() {
        let memoryCapacity = 50 * 1024 * 1024
        let diskCapacity = 100 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
        MainThreadWatchdog.start()
        #if os(macOS)
        // Nicht auf dem Hauptthread: Ein älterer Eintrag kann eine Schlüsselbund-Abfrage auslösen.
        DispatchQueue.global(qos: .utility).async {
            BoxPasswordStore.migrateEntryIfNeeded()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, player: model.player)
            #if os(macOS)
                // Die SwiftUI-Mindesthöhe gilt für den Inhalt ohne Titelleiste (rund 32 pt). Mit 360 wäre
                // das Fenster mindestens 640 × 392 und bei kleinster Breite nie 16:9. 328 + 32 ergibt
                // 640 × 360; die Höhe folgt sonst aus dem Seitenverhältnis (`WindowAspectRatioModifier`).
                .frame(minWidth: 640, minHeight: 328)
                .modifier(WindowAspectRatioModifier(aspectRatio: NSSize(width: 16, height: 9), minSize: NSSize(width: 640, height: 360)))
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 540)
        // Das Bild reicht bis an den oberen Rand; die Fensterknöpfe blenden sich mit der Steuerleiste aus.
        .windowStyle(.hiddenTitleBar)
        #endif
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen…") {
                    model.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            MacCommands(model: model, player: model.player)
        }
        #endif
    }
}

/// Größen und Tastennamen je Plattform. Werte sind für Apple TV (1920×1080) gedacht,
/// auf dem Mac werden sie verkleinert.
enum UI {
    #if os(macOS)
    static let scale: CGFloat = 0.55
    static let select = "Return"
    static let playPause = "Leertaste"
    static let back = "Esc"
    static let leftRight = "←/→"
    static let upDown = "↑/↓"
    #else
    static let scale: CGFloat = 1
    static let select = "Klick"
    static let playPause = "Play/Pause"
    static let back = "Zurück"
    static let leftRight = "Links/Rechts"
    static let upDown = "Hoch/Runter"
    #endif

    /// Uhrzeit „HH:mm“. Einmal angelegt: DateFormatter zu erzeugen ist teuer, und die
    /// Uhrzeiten werden bei jedem Neuzeichnen der Overlays formatiert.
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func s(_ value: CGFloat) -> CGFloat { value * scale }
    /// Apple TV: nie kleiner als 23 pt (Mindestgröße laut Apple-Richtlinien, Standard 29 pt).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        #if os(tvOS)
        .system(size: max(size * scale, minimumFontSize), weight: weight)
        #else
        .system(size: size * scale, weight: weight)
        #endif
    }

    static let minimumFontSize: CGFloat = 23

    static let text = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let secondary = Color(red: 0.66, green: 0.69, blue: 0.74)
    static let panel = Color(red: 0.04, green: 0.08, blue: 0.15).opacity(0.9)
    /// Abdunklung unter durchscheinenden Tafeln über dem Video (Lesbarkeit bei hellem Bild).
    static let panelDim = Color.black.opacity(0.20)
    static let accent = Color(red: 0.50, green: 0.78, blue: 1.0)
}
