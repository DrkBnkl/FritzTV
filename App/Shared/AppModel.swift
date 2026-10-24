import Foundation
import Network
import FritzTVKit

/// Tasten der Siri Remote bzw. der Mac-Tastatur.
enum RemoteCommand: Equatable {
    case up, down, left, right, select, back, playPause
    case digit(Int)
}

/// Was gerade über dem Bild liegt. Die Auswahl in den Overlays verwaltet die App selbst,
/// damit Apple TV und Mac exakt gleich reagieren.
enum Overlay: Equatable {
    case none
    /// Sendungsinfo; Auswahl 0 = Ton, 1 = Untertitel, 2 = Einstellungen.
    case info(selection: Int)
    /// Senderliste; Auswahl −1 = „Mediathek“, 0 = „Platz eingeben“, ab 1 = Senderplatz mit dieser Nummer.
    case channelList(selection: Int, moving: Bool)
    /// Direktwahl; `key` = Taste im Ziffernblock (0…11).
    case directEntry(digits: String, key: Int)
}

enum LoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var lineup: ChannelLineup?
    @Published private(set) var currentNumber = 1
    @Published private(set) var previousKey: String?
    @Published private(set) var connectedHost: String?
    @Published private(set) var bannerVisible = false
    @Published var overlay: Overlay = .none
    @Published var showSettings = false
    @Published var showMediathek = false

    let settings: AppSettings
    let player: PlayerController

    private var catalog: ChannelCatalog?
    private var preferences: LineupPreferences
    private var bannerTask: Task<Void, Never>?
    private var directTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var isWired = false

    static let keypad = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Löschen", "0", "OK"]

    /// Ohne Standardwerte in der Signatur: Standardargumente laufen außerhalb des Main Actors,
    /// der Player muss aber auf dem Main Actor entstehen.
    init(settings: AppSettings? = nil, player: PlayerController? = nil) {
        let resolvedSettings = settings ?? AppSettings()
        self.settings = resolvedSettings
        self.player = player ?? PlayerController()
        if let data = resolvedSettings.lineupData,
           let saved = try? JSONDecoder().decode(LineupPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = .standard
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let wired = path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in self?.isWired = wired }
        }
        pathMonitor.start(queue: DispatchQueue(label: "fritztv.path"))
    }

    // MARK: Senderliste

    var currentEntry: LineupEntry? { lineup?.entry(number: currentNumber) }

    static func key(_ entry: LineupEntry) -> String { entry.group.variants[0].groupKey }

    func load() async {
        loadState = .loading
        DebugLog.log("Lade Senderliste, eigene Adresse: '\(settings.host)'")
        do {
            let result = try await FritzBoxClient(customHost: settings.host).loadCatalog()
            catalog = result.catalog
            connectedHost = result.host
            rebuildLineup()
            loadState = .ready
            DebugLog.log("Senderliste von \(result.host): \(result.catalog.groups.count) Gruppen, \(lineup?.entries.count ?? 0) sichtbare Plätze")
            let start = lineup?.entries.first { Self.key($0) == settings.lastChannelKey }?.number ?? 1
            tune(to: start)
        } catch let error as FritzBoxClient.ClientError {
            DebugLog.log("Senderliste fehlgeschlagen: \(error)")
            switch error {
            case .unreachable:
                loadState = .failed("FRITZ!Box nicht erreichbar. Ist das Heimnetz oder das VPN verbunden?")
            case .noChannels:
                loadState = .failed("Keine Sender gefunden. Ist Live-TV unter DVB-C eingeschaltet und ein Sendersuchlauf gelaufen?")
            }
        } catch {
            DebugLog.log("Senderliste fehlgeschlagen: \(error)")
            loadState = .failed(error.localizedDescription)
        }
    }

    private func rebuildLineup() {
        guard let catalog else { return }
        let rebuilt = ChannelLineup(catalog: catalog, preferences: preferences)
        lineup = rebuilt
        if let number = rebuilt.entries.first(where: { Self.key($0) == settings.lastChannelKey })?.number {
            currentNumber = number
        } else {
            currentNumber = min(max(currentNumber, 1), max(rebuilt.entries.count, 1))
        }
    }

    private func savePreferences() {
        settings.lineupData = try? JSONEncoder().encode(preferences)
        rebuildLineup()
    }

    // MARK: Umschalten

    func tune(to number: Int) {
        guard let entry = lineup?.entry(number: number) else { return }
        if let old = currentEntry, old.id != entry.id {
            previousKey = Self.key(old)
        }
        currentNumber = entry.number
        settings.lastChannelKey = Self.key(entry)
        let candidates = entry.group.candidates(preferHD: settings.preferHD)
        DebugLog.log("Umschalten auf \(entry.number) \(entry.group.displayName): \(candidates.count) Variante(n), zuerst \(candidates.first?.streamURL.absoluteString ?? "-") \(playbackOptions())")
        player.play(candidates: candidates, options: playbackOptions())
        showBanner()
    }

    private func zap(_ step: Int) {
        guard let next = lineup?.entry(after: currentNumber, step: step) else { return }
        tune(to: next.number)
    }

    func playbackOptions() -> PlaybackOptions {
        PlaybackOptions(
            networkCachingMs: settings.networkCaching > 0 ? settings.networkCaching : (isWired ? 500 : 1000),
            rtspTCP: settings.rtspTCP,
            deinterlace: settings.deinterlaceSD,
            audioDelayMs: settings.audioDelayMs,
            timeshift: settings.timeshift
        )
    }

    /// Nach dem Schließen der Einstellungen: Stream nur neu starten, wenn sich etwas geändert hat.
    func applySettings() {
        guard let entry = currentEntry else { return }
        let candidates = entry.group.candidates(preferHD: settings.preferHD)
        let sameChannel = player.channel.map { current in candidates.contains { $0.id == current.id } } ?? false
        if !sameChannel || candidates.first?.isHD != player.channel?.isHD || playbackOptions() != player.options {
            player.play(candidates: candidates, options: playbackOptions())
        }
    }

    func resume() {
        if player.status == .idle, let entry = currentEntry {
            player.play(candidates: entry.group.candidates(preferHD: settings.preferHD), options: playbackOptions())
        }
    }

    // MARK: Infoleiste

    func showBanner() {
        bannerVisible = true
        bannerTask?.cancel()
        let seconds = settings.bannerSeconds
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.bannerVisible = false }
        }
    }

    func programChanged() {
        if overlay == .none { showBanner() }
    }

    // MARK: Tasten

    func handle(_ command: RemoteCommand) {
        switch loadState {
        case .loading:
            return
        case .failed:
            if command == .select { Task { await load() } }
            if command == .playPause { showSettings = true }
            return
        case .ready:
            break
        }

        switch overlay {
        case .none:
            handleLive(command)
        case .info(let selection):
            handleInfo(command, selection: selection)
        case .channelList(let selection, let moving):
            handleList(command, selection: selection, moving: moving)
        case .directEntry(let digits, let key):
            handleDirect(command, digits: digits, key: key)
        }
    }

    private func handleLive(_ command: RemoteCommand) {
        switch command {
        case .up: zap(+1)
        case .down: zap(-1)
        case .select:
            bannerVisible = false
            overlay = .info(selection: 0)
        case .back: openChannelList()
        case .playPause: player.togglePause()
        case .left: player.jump(seconds: -10)
        case .right: player.jump(seconds: 10)
        case .digit(let digit): enterDigit(digit, into: "", key: 0)
        }
    }

    private func handleInfo(_ command: RemoteCommand, selection: Int) {
        switch command {
        case .left: overlay = .info(selection: max(selection - 1, 0))
        case .right: overlay = .info(selection: min(selection + 1, 2))
        case .select:
            switch selection {
            case 0: player.cycleAudioTrack()
            case 1: player.cycleSubtitle()
            default:
                overlay = .none
                showSettings = true
            }
        case .back, .up, .down: overlay = .none
        case .playPause: player.togglePause()
        case .digit: break
        }
    }

    private func openChannelList() {
        bannerVisible = false
        let target = lineup?.entries.first { Self.key($0) == previousKey }?.number ?? currentNumber
        overlay = .channelList(selection: target, moving: false)
    }

    private func handleList(_ command: RemoteCommand, selection: Int, moving: Bool) {
        let last = lineup?.entries.count ?? 0
        switch command {
        case .up, .down:
            let step = command == .up ? -1 : 1
            if moving {
                if moveEntry(number: selection, by: step) {
                    overlay = .channelList(selection: selection + step, moving: true)
                }
            } else {
                // Reihen −1 (Mediathek) bis `last`, mit Umlauf
                var next = selection + step
                if next < -1 { next = last }
                if next > last { next = -1 }
                overlay = .channelList(selection: next, moving: false)
            }
        case .select:
            if moving {
                overlay = .channelList(selection: selection, moving: false)
            } else if selection == -1 {
                openMediathek()
            } else if selection == 0 {
                overlay = .directEntry(digits: "", key: 0)
            } else {
                overlay = .none
                tune(to: selection)
            }
        case .playPause:
            if selection > 0 { overlay = .channelList(selection: selection, moving: !moving) }
        case .back:
            overlay = moving ? .channelList(selection: selection, moving: false) : .none
        case .left, .right:
            break
        case .digit(let digit):
            enterDigit(digit, into: "", key: 0)
        }
    }

    private func handleDirect(_ command: RemoteCommand, digits: String, key: Int) {
        switch command {
        case .left: overlay = .directEntry(digits: digits, key: key % 3 > 0 ? key - 1 : key)
        case .right: overlay = .directEntry(digits: digits, key: key % 3 < 2 ? key + 1 : key)
        case .up: overlay = .directEntry(digits: digits, key: key >= 3 ? key - 3 : key)
        case .down: overlay = .directEntry(digits: digits, key: key < 9 ? key + 3 : key)
        case .select:
            switch key {
            case 0...8: enterDigit(key + 1, into: digits, key: key)
            case 9: overlay = .directEntry(digits: String(digits.dropLast()), key: key)
            case 10: enterDigit(0, into: digits, key: key)
            default: commitDirect(digits)
            }
        case .playPause: commitDirect(digits)
        case .back:
            directTask?.cancel()
            overlay = .none
        case .digit(let digit): enterDigit(digit, into: digits, key: key)
        }
    }

    private func enterDigit(_ digit: Int, into digits: String, key: Int) {
        let updated = String((digits + String(digit)).suffix(3))
        overlay = .directEntry(digits: updated, key: key)
        directTask?.cancel()
        directTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.commitDirect(updated) }
        }
    }

    private func commitDirect(_ digits: String) {
        directTask?.cancel()
        guard case .directEntry = overlay else { return }
        if let number = Int(digits), lineup?.entry(number: number) != nil {
            overlay = .none
            tune(to: number)
        } else {
            overlay = .directEntry(digits: "", key: 11)
        }
    }

    func directPreview(_ digits: String) -> LineupEntry? {
        Int(digits).flatMap { lineup?.entry(number: $0) }
    }

    // MARK: Mediathek

    /// Öffnet die Mediathek-Seite. Der Fernsehstream wird angehalten, damit Tuner und Bandbreite frei sind.
    func openMediathek() {
        overlay = .none
        bannerVisible = false
        player.stop()
        showMediathek = true
    }

    func mediathekClosed() {
        resume()
    }

    // MARK: Senderplätze bearbeiten

    /// Verschiebt den Sender auf Platz `number` um `delta` Plätze.
    @discardableResult
    private func moveEntry(number: Int, by delta: Int) -> Bool {
        guard let entries = lineup?.entries else { return false }
        var keys = entries.map(Self.key)
        let from = number - 1, to = number - 1 + delta
        guard keys.indices.contains(from), keys.indices.contains(to) else { return false }
        keys.swapAt(from, to)
        let visible = Set(keys)
        preferences.order = keys + preferences.order.filter { !visible.contains($0) }
        savePreferences()
        return true
    }

    func hideCurrentChannel() {
        guard let entry = currentEntry else { return }
        preferences.hidden.insert(Self.key(entry))
        savePreferences()
        tune(to: min(currentNumber, lineup?.entries.count ?? 1))
    }

    func unhide(_ group: ChannelGroup) {
        let key = group.variants[0].groupKey
        preferences.hidden.remove(key)
        savePreferences()
    }

    func resetLineup() {
        preferences = .standard
        savePreferences()
    }
}
