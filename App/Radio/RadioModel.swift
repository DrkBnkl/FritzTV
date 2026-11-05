import AppKit
import Combine
import MediaPlayer
import ServiceManagement
import FritzTVKit

/// Zustand von FritzRadio: Senderliste der Box, laufender Sender, Favoriten und Einstellungen.
@MainActor
final class RadioModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var stations = RadioStations()
    /// Gewählter Sender, auch wenn er gerade angehalten ist.
    @Published private(set) var current: ChannelGroup?
    /// Hinweis, wenn ein Sender keinen Ton liefert.
    @Published private(set) var problem: String?
    @Published var searchText = ""
    /// Einstellungen statt Senderliste zeigen (Menüleiste und Fenster gemeinsam).
    @Published var showsSettings = false
    /// Zählt hoch, wenn das Suchfeld den Fokus bekommen soll (⌘F).
    @Published private(set) var searchFocusRequest = 0

    @Published var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    /// Tonformat und Bitrate des laufenden Senders im Panel zeigen.
    @Published var showsAudioFormat: Bool { didSet { defaults.set(showsAudioFormat, forKey: Keys.showsAudioFormat) } }
    @Published var volume: Int {
        didSet {
            defaults.set(volume, forKey: Keys.volume)
            player.volume = volume
        }
    }
    @Published private(set) var favoriteKeys: [String] { didSet { defaults.set(favoriteKeys, forKey: Keys.favorites) } }
    @Published private(set) var recentKeys: [String] { didSet { defaults.set(recentKeys, forKey: Keys.recent) } }
    @Published private(set) var deadIDs: Set<String> { didSet { defaults.set(Array(deadIDs), forKey: Keys.dead) } }
    private var workingVariantIDs: [String: String] { didSet { defaults.set(workingVariantIDs, forKey: Keys.working) } }

    let player: RadioPlayer
    private let defaults = UserDefaults.standard
    private var connectedHost: String?
    /// Soll Ton laufen? Bleibt über Ruhezustand und Verbindungsabrisse hinweg gesetzt.
    private var wantsPlayback = false
    private var activity: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        host = defaults.string(forKey: Keys.host) ?? ""
        volume = defaults.object(forKey: Keys.volume) as? Int ?? 80
        showsAudioFormat = defaults.object(forKey: Keys.showsAudioFormat) as? Bool ?? true
        favoriteKeys = defaults.stringArray(forKey: Keys.favorites) ?? []
        recentKeys = defaults.stringArray(forKey: Keys.recent) ?? []
        deadIDs = Set(defaults.stringArray(forKey: Keys.dead) ?? [])
        workingVariantIDs = defaults.dictionary(forKey: Keys.working) as? [String: String] ?? [:]
        player = RadioPlayer(epgCacheURL: Self.epgCacheURL)
        player.volume = volume

        player.onVariantSuccess = { [weak self] variant, failed in
            self?.variantWorks(variant, failed: failed)
        }
        player.onAllVariantsFailed = { [weak self] failed, silent in
            self?.allVariantsFailed(failed, silent: silent)
        }
        // Ansichten, die nur das Modell beobachten, sollen Statuswechsel des Players mitbekommen.
        player.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        player.$status
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateNowPlaying() }
            }
            .store(in: &cancellables)
        player.$epgRevision
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateNowPlaying() }
            }
            .store(in: &cancellables)

        setUpRemoteCommands()
        observeSleep()
        Task { await load() }
    }

    private static var epgCacheURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "de.home.fritzradio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("epg_cache.json")
    }

    // MARK: Senderliste

    func load() async {
        loadState = .loading
        do {
            let customHost = host.trimmingCharacters(in: .whitespaces)
            let result = try await FritzBoxClient(customHost: customHost.isEmpty ? nil : customHost).loadCatalog()
            connectedHost = result.host
            stations = RadioStations(catalog: result.catalog)
            radioLog.notice("\(self.stations.all.count) Radiosender von \(result.host, privacy: .public)")
            loadState = stations.all.isEmpty ? .failed("Die FRITZ!Box meldet keine Radiosender.") : .ready
            if current == nil, let last = defaults.string(forKey: Keys.last) {
                current = stations.all.first { $0.key == last }
            }
        } catch {
            radioLog.error("Senderliste nicht geladen: \(error.localizedDescription, privacy: .public)")
            loadState = .failed("FRITZ!Box nicht erreichbar. Adresse in den Einstellungen prüfen.")
        }
    }

    var sections: [RadioListSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty else {
            let hits = stations.all.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
            return hits.isEmpty ? [] : [RadioListSection(id: "search", title: "TREFFER", stations: hits)]
        }
        return stations.sections(favoriteKeys: favoriteKeys, recentKeys: recentKeys, deadIDs: deadIDs)
    }

    func isFavorite(_ group: ChannelGroup) -> Bool { favoriteKeys.contains(group.key) }

    func isDead(_ group: ChannelGroup) -> Bool { group.areAllVariantsDead(deadIDs: deadIDs) }

    func toggleFavorite(_ group: ChannelGroup) {
        if isFavorite(group) {
            favoriteKeys.removeAll { $0 == group.key }
        } else {
            favoriteKeys.append(group.key)
        }
    }

    /// Gibt Sender ohne Empfang wieder frei, z. B. nach einem Sendersuchlauf.
    func resetDeadStations() {
        deadIDs = []
        workingVariantIDs = [:]
    }

    // MARK: Wiedergabe

    var isPlaying: Bool { wantsPlayback }

    func play(_ group: ChannelGroup) {
        current = group
        problem = nil
        wantsPlayback = true
        defaults.set(group.key, forKey: Keys.last)
        recentKeys = RadioStations.recording(key: group.key, in: recentKeys)
        var candidates = group.candidates(preferHD: false, deadIDs: deadIDs)
        if let working = workingVariantIDs[group.key], let index = candidates.firstIndex(where: { $0.id == working }) {
            candidates.insert(candidates.remove(at: index), at: 0)
        }
        player.play(candidates: candidates)
        keepAwake(true)
    }

    func stop() {
        wantsPlayback = false
        player.stop()
        keepAwake(false)
    }

    func togglePlayback() {
        if wantsPlayback {
            stop()
        } else if let current {
            play(current)
        } else if let first = sections.first?.stations.first {
            play(first)
        }
    }

    /// Ändert die Lautstärke in Schritten, z. B. per Tastatur.
    func changeVolume(by delta: Int) {
        volume = min(max(volume + delta, 0), 100)
    }

    /// Favoriten in der Reihenfolge der Liste, für ⌘1 bis ⌘9.
    var favorites: [ChannelGroup] {
        favoriteKeys.compactMap { key in stations.all.first { $0.key == key } }
    }

    func playFavorite(at index: Int) {
        let list = favorites
        guard list.indices.contains(index) else { return }
        play(list[index])
    }

    /// Spielt den ersten Suchtreffer (Return im Suchfeld).
    func playFirstHit() {
        guard let first = sections.first?.stations.first else { return }
        play(first)
    }

    func focusSearch() {
        showsSettings = false
        searchFocusRequest += 1
    }

    /// Nächster bzw. voriger Sender in der Reihenfolge der Senderfamilien.
    func step(_ offset: Int) {
        guard let current, let next = stations.station(after: current, step: offset) else { return }
        play(next)
    }

    private func variantWorks(_ variant: Channel, failed: [Channel]) {
        guard let current else { return }
        workingVariantIDs[current.key] = variant.id
        deadIDs.remove(variant.id)
        // Eine andere Variante läuft: Die gescheiterten sind veraltete Einträge.
        deadIDs.formUnion(failed.map(\.id))
    }

    private func allVariantsFailed(_ failed: [Channel], silent: [Channel]) {
        wantsPlayback = false
        keepAwake(false)
        let station = current
        let name = station?.displayName ?? "Sender"
        problem = "Kein Ton für \(name)."
        guard let host = connectedHost else { return }
        Task {
            let status = await FritzBoxTunerClient().fetchStatus(host: host)
            guard self.current == station, !self.wantsPlayback else { return }
            if status?.allTunersBusy == true {
                problem = "Alle Tuner der FRITZ!Box sind belegt."
            } else if status != nil || !silent.isEmpty {
                // Tuner frei (bzw. ohne UPnP-Statusinfos: Box nahm die Verbindung an, blieb aber stumm):
                // Der Sender kommt ans Ende der Liste, bis er wieder Ton liefert oder ein
                // Sendersuchlauf neue Einträge bringt.
                deadIDs.formUnion((status != nil ? failed : silent).map(\.id))
                problem = "Kein Ton für \(name). Die Senderliste der Box ist womöglich veraltet."
            } else {
                problem = "Die FRITZ!Box lehnt die Verbindung ab. Womöglich sind alle Tuner belegt."
            }
        }
    }

    /// Solange Radio läuft, schläft der Mac nicht ein; der Bildschirm darf aus.
    private func keepAwake(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: "Radio läuft")
        } else if !on, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    /// Im Ruhezustand reißt der Stream ab: vorher anhalten, danach neu verbinden.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsPlayback else { return }
                self.player.stop()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsPlayback, let current = self.current else { return }
                // Das Netzwerk braucht nach dem Aufwachen einen Moment.
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if self.wantsPlayback, self.current == current { self.play(current) }
                }
            }
        }
    }

    // MARK: Programminfo

    func currentProgram(of group: ChannelGroup) -> EPGProgram? {
        real(player.epgStore.currentProgram(forChannelNames: group.epgNames))
    }

    func nextProgram(of group: ChannelGroup) -> EPGProgram? {
        real(player.epgStore.nextProgram(forChannelNames: group.epgNames))
    }

    private func real(_ program: EPGProgram?) -> EPGProgram? {
        guard let program, !EPGProgram.isPlaceholderTitle(program.title) else { return nil }
        return program
    }

    // MARK: Mediensteuerung (Medientasten, Kontrollzentrum)

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayback() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.wantsPlayback == false { self?.togglePlayback() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.step(+1) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.step(-1) }
            return .success
        }
    }

    func updateNowPlaying() {
        let info = MPNowPlayingInfoCenter.default()
        guard let current else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: currentProgram(of: current)?.title ?? current.displayName,
            MPMediaItemPropertyArtist: current.displayName,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        if let logo = RadioLogoCache.shared.image(for: current.displayName) {
            values[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: logo.size) { _ in logo }
        }
        info.nowPlayingInfo = values
        info.playbackState = wantsPlayback ? .playing : .paused
    }

    // MARK: Anmeldeobjekt

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                problem = "Anmeldeobjekt ließ sich nicht ändern: \(error.localizedDescription)"
            }
        }
    }

    private enum Keys {
        static let host = "host"
        static let volume = "volume"
        static let favorites = "favoriteKeys"
        static let recent = "recentKeys"
        static let dead = "deadChannelIDs"
        static let working = "workingVariantIDs"
        static let last = "lastStationKey"
        static let showsAudioFormat = "showsAudioFormat"
    }
}
