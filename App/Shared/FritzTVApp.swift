import SwiftUI

@main
struct FritzTVApp: App {
    @StateObject private var model = AppModel()

    init() {
        let memoryCapacity = 50 * 1024 * 1024
        let diskCapacity = 100 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
        #if DEBUG
        MainThreadWatchdog.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, player: model.player)
            #if os(macOS)
                .frame(minWidth: 960, minHeight: 540)
            #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen…") {
                    model.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    static let text = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let secondary = Color(red: 0.66, green: 0.69, blue: 0.74)
    static let panel = Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.9)
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.42)
}
