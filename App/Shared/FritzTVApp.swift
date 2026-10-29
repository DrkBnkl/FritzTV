import SwiftUI

@main
struct FritzTVApp: App {
    @StateObject private var model = AppModel()

    init() {
        let memoryCapacity = 50 * 1024 * 1024
        let diskCapacity = 100 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
        MainThreadWatchdog.start()
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
            CommandMenu("Steuerung") {
                Button("Programmübersicht") {
                    if model.showEPGOverview {
                        model.closeEPGOverview()
                    } else {
                        model.openEPGOverview()
                    }
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Sendungsinfo") {
                    if case .info = model.overlay {
                        model.overlay = .none
                    } else {
                        model.openInfoPanel()
                    }
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Senderliste") {
                    if case .channelList = model.overlay {
                        model.overlay = .none
                    } else {
                        model.openChannelList()
                    }
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Anhalten / Weiter (Timeshift)") {
                    model.player.togglePause()
                    model.showBanner()
                }
                .keyboardShortcut("p", modifiers: .command)

                if model.player.isTimeshifted {
                    Button("Zum Live-Bild springen") {
                        model.player.goLive()
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }

                Divider()

                Button("Nächster Sender") {
                    model.handle(.up)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Vorheriger Sender") {
                    model.handle(.down)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
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
