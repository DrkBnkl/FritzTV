import Foundation
import SwiftUI
import Network
import FritzTVKit
#if os(tvOS)
import TVServices
#elseif os(macOS)
import AppKit
#endif

/// Tasten der Siri Remote bzw. der Mac-Tastatur.
enum RemoteCommand: Equatable {
    case up, down, left, right, select, back, playPause
    case digit(Int)
    /// Seitentasten kompatibler Fernbedienungen: im Live-Bild Sender wechseln, in Listen blättern.
    case pageUp, pageDown
    /// Wischen auf der Touch-Fläche (Apple TV): im Live-Bild Senderleiste bzw. Info öffnen.
    case swipeUp, swipeDown
}

/// Was gerade über dem Bild liegt. Die Auswahl in den Overlays verwaltet die App selbst,
/// damit Apple TV und Mac exakt gleich reagieren.
enum Overlay: Equatable {
    case none
    /// Sendungsinfo; Auswahl 0 = Ton, 1 = Untertitel, 2 = Einstellungen.
    case info(selection: Int)
    /// Senderliste; `selectedID` identifiziert die ausgewählte Zeile.
    case channelList(selectedID: String)
    /// Direktwahl; `key` = Taste im Ziffernblock (0…11).
    case directEntry(digits: String, key: Int)
    /// Senderleiste am unteren Rand (Wischen nach oben); `index` in der Senderliste.
    case footer(index: Int)
}

struct ManagedChannel: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let displayName: String
    let isHD: Bool
    let group: ChannelGroup
    let number: Int?
    let isHidden: Bool
}

/// Element in der Senderliste für Tastennavigation und Fokus.
enum ChannelListItem: Hashable, Identifiable {
    case epgOverview
    case recent(LineupEntry)
    case channel(LineupEntry)
    case settings

    var id: String {
        switch self {
        case .epgOverview: return "epgOverview"
        case .recent(let entry): return "recent-\(entry.number)"
        case .channel(let entry): return "channel-\(entry.number)"
        case .settings: return "settings"
        }
    }
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
    /// Schlüssel des Senders, der gerade abgespielt wird. Ein Schlüssel statt einer Platznummer,
    /// weil sich Nummern beim Verschieben, Ausblenden oder Neuladen der Liste ändern.
    private var playingKey: String?
    @Published private(set) var previousKey: String?
    @Published private(set) var connectedHost: String?
    @Published private(set) var bannerVisible = false
    @Published var overlay: Overlay = .none {
        didSet {
            if case .info = overlay { player.collectStats = true } else { player.collectStats = false }
            if overlay != .none {
                bannerTask?.cancel()
                bannerVisible = false
            }
            if case .footer = overlay {} else {
                footerHideTask?.cancel()
            }
            if case .directEntry = overlay {} else {
                directTask?.cancel()
            }
        }
    }
    /// Link (Top Shelf, `fritztv://`), der vor dem Laden der Senderliste ankam.
    private var pendingDeepLink: URL?
    @Published var showSettings = false
    @Published var showEPGOverview = false
    /// Umschalten aus der Programmübersicht: Bild abdecken, bis der neue Sender ein Bild zeigt
    /// (unabhängig von der Einstellung „Schwarzer Bildschirm beim Umschalten“).
    @Published var zapFromEPG = false
    /// Auswahl in der Programmübersicht. Eigenes Objekt: Änderungen zeichnen nur die Übersicht
    /// neu, nicht die ganze App (wichtig für ruhiges Blättern auf dem Apple TV).
    let epgNav = EPGNavigation()
    /// Ausgewählter Sender in der Programmübersicht (Senderschlüssel). Die Auswahl verwaltet die
    /// App selbst wie bei der Senderliste: Alle Tasten laufen über `handle`, auf Apple TV und Mac gleich.
    private(set) var epgSelectedKey: String? {
        get { epgNav.selectedKey }
        set { if epgNav.selectedKey != newValue { epgNav.selectedKey = newValue } }
    }
    /// Zeitpunkt in der Programmübersicht, den Links/Rechts ansteuert; `nil` = jetzt.
    var epgCursorTime: Date? {
        get { epgNav.cursorTime }
        set { if epgNav.cursorTime != newValue { epgNav.cursorTime = newValue } }
    }
    @Published var activeHLSReplay: (url: URL, startDate: Date?)?
    @Published var activeMediathekURL: URL?
    /// Untertitel zum laufenden Mediathek-Video aus der Suche, falls vorhanden.
    private(set) var activeMediathekSubtitle: URL?
    @Published var searchResultDialog: (title: String, results: [MediathekSearchResult])?

    let settings: AppSettings
    let player: PlayerController
    let stationSearch = StationSearchController()

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
        let resolvedPlayer = player ?? PlayerController()
        self.settings = resolvedSettings
        self.player = resolvedPlayer
        if let data = resolvedSettings.lineupData,
           let saved = try? JSONDecoder().decode(LineupPreferences.self, from: data) {
            preferences = saved.normalized
        } else {
            preferences = .standard
        }

        resolvedPlayer.onVariantSuccess = { [weak self] variantKey, workingID, failedEarlier in
            Task { @MainActor in
                if let workingID {
                    self?.settings.markVariantWorking(variantKey: variantKey, channelID: workingID)
                }
                for failed in failedEarlier {
                    self?.settings.markVariantDead(channelID: failed)
                }
            }
        }

        resolvedPlayer.onAllCandidatesFailed = { [weak self] channelName in
            Task { @MainActor in
                guard let self else { return }
                let failedKey = self.playingKey
                if let tunerStatus = await FritzBoxTunerClient().fetchStatus(host: self.boxHost) {
                    // Die Abfrage dauert: Inzwischen umgeschaltet oder Bild da? Dann nichts überschreiben.
                    guard self.playingKey == failedKey, case .failed = self.player.status else { return }
                    if tunerStatus.allTunersBusy {
                        self.player.setFailed(
                            title: "Alle \(tunerStatus.totalTuners) Tuner belegt",
                            message: "Die FRITZ!Box kann derzeit keinen freien Tuner bereitstellen.",
                            hint: "Ein anderes Gerät im Heimnetz nutzt bereits Live-TV."
                        )
                    }
                }
            }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let wired = path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in self?.isWired = wired }
        }
        pathMonitor.start(queue: DispatchQueue(label: "fritztv.path"))
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: Senderliste

    var currentEntry: LineupEntry? { lineup?.entry(number: currentNumber) }

    /// Zuletzt gesehene Sender, maximal 2 Plätze.
    var recentEntries: [LineupEntry] {
        guard let lineup else { return [] }
        return settings.recentKeys.prefix(2).compactMap { key in
            lineup.entries.first { Self.key($0) == key }
        }
    }

    /// Alle ansteuerbaren Einträge in der Senderliste in Darstellungsreihenfolge.
    var channelListItems: [ChannelListItem] {
        var items: [ChannelListItem] = [.epgOverview]
        for entry in recentEntries {
            items.append(.recent(entry))
        }
        for entry in lineup?.entries ?? [] {
            items.append(.channel(entry))
        }
        items.append(.settings)
        return items
    }

    static func key(_ entry: LineupEntry) -> String { entry.group.variants[0].groupKey }

    /// Adresse der Box: eigene Eingabe, sonst die beim Laden gefundene.
    var boxHost: String {
        settings.host.isEmpty ? (connectedHost ?? "fritz.box") : settings.host
    }

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
            if let link = pendingDeepLink {
                pendingDeepLink = nil
                if handleDeepLink(url: link) { return }
            }
            let start = lineup?.entries.first { Self.key($0) == settings.lastChannelKey }?.number ?? 1
            tune(to: start)
            refreshInternetEPG()
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
        syncTopShelf()
        let anchorKey = playingKey ?? settings.lastChannelKey
        if let number = rebuilt.entries.first(where: { Self.key($0) == anchorKey })?.number {
            currentNumber = number
        } else {
            currentNumber = min(max(currentNumber, 1), max(rebuilt.entries.count, 1))
        }
    }

    private func syncTopShelf() {
        guard let lineup else { return }
        let top = lineup.entries.prefix(12).map { entry in
            TopShelfChannel(
                number: entry.number,
                name: entry.group.displayName,
                groupKey: Self.key(entry),
                isHD: entry.group.hd != nil
            )
        }
        if TopShelfStore.save(channels: Array(top)) {
            #if os(tvOS)
            // Sonst zeigt das Top Shelf die alte Reihenfolge, bis tvOS es von selbst neu lädt.
            TVTopShelfContentProvider.topShelfContentDidChange()
            #endif
        }
    }

    private func savePreferences() {
        settings.lineupData = try? JSONEncoder().encode(preferences)
        rebuildLineup()
    }

    // MARK: Umschalten

    private var zapDebounceTask: Task<Void, Never>?

    func tune(to number: Int) {
        zapDebounceTask?.cancel()
        zapDebounceTask = nil
        performTune(to: number)
    }

    /// Bricht ein noch nicht ausgeführtes Umschalten ab und stellt die Nummer des laufenden
    /// Senders wieder her (z. B. wenn auf dem Apple TV eine Wischgeste kurz nach einem
    /// ausgelösten `onMoveCommand` als Overlay-Öffnen erkannt wird).
    func cancelPendingZap() {
        guard zapDebounceTask != nil else { return }
        zapDebounceTask?.cancel()
        zapDebounceTask = nil
        if let playingKey,
           let playingEntry = lineup?.entries.first(where: { Self.key($0) == playingKey }) {
            currentNumber = playingEntry.number
        }
    }

    private func zap(_ step: Int) {
        guard let next = lineup?.entry(after: currentNumber, step: step) else { return }
        currentNumber = next.number
        showBanner()
        zapDebounceTask?.cancel()
        zapDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            // Erledigt: sonst gilt der nächste Klick weiter als „Umschalten bestätigen“
            // statt die Sendungsinfo zu öffnen.
            self.zapDebounceTask = nil
            self.performTune(to: next.number)
        }
    }

    private func performTune(to number: Int) {
        guard let entry = lineup?.entry(number: number) else { return }
        let key = Self.key(entry)
        #if os(macOS)
        let hasActiveDrawableWindow = (player.mediaPlayer.drawable as? NSView)?.window != nil
        #else
        let hasActiveDrawableWindow = true
        #endif
        if playingKey == key, hasActiveDrawableWindow {
            switch player.status {
            case .failed, .idle:
                break   // neu versuchen
            default:
                // Läuft schon (auch angehalten im Timeshift oder beim Verbinden): nicht neu starten.
                currentNumber = entry.number
                showBanner()
                return
            }
        }
        if let oldKey = playingKey, oldKey != key {
            previousKey = oldKey
            settings.recordRecent(key: oldKey, currentKey: key)
        }
        currentNumber = entry.number
        settings.lastChannelKey = key
        play(entry)
        showBanner()
    }

    /// Spielt einen Senderplatz mit allen Varianten, die gemerkte funktionierende zuerst.
    private func play(_ entry: LineupEntry) {
        playingKey = Self.key(entry)
        let candidates = currentCandidates(for: entry)
        let preferredID = settings.workingVariantIDs[candidates.variantKey]
        DebugLog.log("Umschalten auf \(entry.number) \(entry.group.displayName): \(candidates.count) Variante(n), zuerst \(candidates.first?.streamURL.absoluteString ?? "-") \(playbackOptions())")
        player.play(candidates: candidates, options: playbackOptions(), preferredVariantID: preferredID)
    }

    private func currentCandidates(for entry: LineupEntry) -> [Channel] {
        entry.group.candidates(preferHD: settings.preferHD, deadIDs: settings.deadChannelIDs)
    }

    func playbackOptions() -> PlaybackOptions {
        PlaybackOptions(
            networkCachingMs: settings.networkCaching > 0 ? settings.networkCaching : (isWired ? 500 : 1000),
            rtspTCP: settings.rtspTCP,
            deinterlace: settings.deinterlaceSD,
            audioDelayMs: settings.audioDelayMs,
            audioDelayAC3Ms: settings.audioDelayAC3Ms,
            timeshift: settings.timeshift,
            timeshiftMinutes: settings.timeshiftMinutes
        )
    }

    /// Nach dem Schließen der Einstellungen: Stream nur neu starten, wenn sich etwas geändert hat.
    func applySettings() {
        guard let entry = currentEntry else { return }
        let candidates = currentCandidates(for: entry)
        let sameChannel = player.channel.map { current in candidates.contains { $0.id == current.id } } ?? false
        if !sameChannel || candidates.first?.isHD != player.channel?.isHD || playbackOptions() != player.options {
            play(entry)
        }
    }

    func resume() {
        guard let entry = currentEntry else { return }
        play(entry)
    }

    /// App kommt in den Vordergrund. Nur fortsetzen, wenn der Stream wirklich angehalten wurde
    /// (Hintergrund) – nicht nach kurzem `inactive` (z. B. Kontrollzentrum), sonst wären
    /// Timeshift-Puffer und Position weg – und nicht, solange ein anderer Player offen ist.
    func returnedToForeground() {
        refreshInternetEPG()
        guard loadState == .ready, player.status == .idle,
              activeHLSReplay == nil, activeMediathekURL == nil else { return }
        resume()
    }

    // MARK: Infoleiste

    func showBanner() {
        bannerTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            bannerVisible = true
        }
        let seconds = settings.bannerSeconds
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self?.bannerVisible = false
                    }
                }
            }
        }
    }

    func programChanged() {
        if isPlainLiveView && !player.isTimeshifted {
            showBanner()
        }
    }

    // MARK: Tasten

    func handle(_ command: RemoteCommand) {
        if command == .back { DebugLog.log("Taste: zurück") }
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

        if showEPGOverview {
            handleEPG(command)
            return
        }

        switch overlay {
        case .none:
            handleLive(command)
        case .footer(let index):
            handleFooter(command, index: index)
        case .info(let selection):
            handleInfo(command, selection: selection)
        case .channelList(let selectedID):
            handleList(command, selectedID: selectedID)
        case .directEntry(let digits, let key):
            handleDirect(command, digits: digits, key: key)
        }
    }

    private func handleLive(_ command: RemoteCommand) {
        switch command {
        case .up: zap(+1)
        case .down: zap(-1)
        case .select:
            // Im Timeshift immer die Sendungsinfo (nie neu einschalten).
            if player.isReplaying {
                bannerVisible = false
                overlay = .info(selection: 0)
                refreshTunerStats()
                return
            }
            if zapDebounceTask != nil {
                tune(to: currentNumber)
                return
            }
            if case .failed = player.status {
                tune(to: currentNumber)
            } else if player.status == .idle {
                resume()
            } else {
                bannerVisible = false
                overlay = .info(selection: 0)
                refreshTunerStats()
            }
        case .back: openChannelList()
        case .playPause:
            if player.status == .idle {
                resume()
            } else {
                player.togglePause()
                if player.pausedSince == nil {
                    showBanner()
                }
            }
        case .left:
            player.jumpProgressive(forward: false)
            showBanner()
        case .right:
            player.jumpProgressive(forward: true)
            showBanner()
        case .digit(let digit): enterDigit(digit, into: "", key: 0)
        case .pageUp: zap(+1)
        case .pageDown: zap(-1)
        case .swipeUp:
            cancelPendingZap()
            openFooter()
        case .swipeDown:
            cancelPendingZap()
            bannerVisible = false
            overlay = .info(selection: 0)
            refreshTunerStats()
        }
    }

    /// Ist das Live-Bild ohne Overlay zu sehen? Dann gelten Klick oben/unten (zappen) und Wischen
    /// (Senderleiste/Info) getrennt, siehe `RemoteInputModifier`.
    var isPlainLiveView: Bool {
        guard case .ready = loadState else { return false }
        return overlay == .none && !showEPGOverview && !showSettings
            && searchResultDialog == nil && activeHLSReplay == nil && activeMediathekURL == nil
    }

    // MARK: Senderleiste unten (Apple: „content footer“)

    private var footerHideTask: Task<Void, Never>?

    private func openFooter() {
        guard let entries = lineup?.entries, !entries.isEmpty else { return }
        bannerVisible = false
        let index = entries.firstIndex { $0.number == currentNumber } ?? 0
        overlay = .footer(index: index)
        scheduleFooterHide()
    }

    /// Ohne Bedienung blendet sich die Leiste nach 8 Sekunden aus.
    private func scheduleFooterHide() {
        footerHideTask?.cancel()
        footerHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, case .footer = self.overlay else { return }
            withAnimation(.easeInOut(duration: 0.3)) { self.overlay = .none }
        }
    }

    private func handleFooter(_ command: RemoteCommand, index: Int) {
        guard let entries = lineup?.entries, !entries.isEmpty else { overlay = .none; return }
        scheduleFooterHide()
        switch command {
        case .left: overlay = .footer(index: max(index - 1, 0))
        case .right: overlay = .footer(index: min(index + 1, entries.count - 1))
        case .pageUp: overlay = .footer(index: max(index - 5, 0))
        case .pageDown: overlay = .footer(index: min(index + 5, entries.count - 1))
        case .select:
            let entry = entries[min(index, entries.count - 1)]
            footerHideTask?.cancel()
            overlay = .none
            tune(to: entry.number)
        case .back, .down, .swipeDown:
            footerHideTask?.cancel()
            overlay = .none
        case .playPause: player.togglePause()
        case .up, .swipeUp: break
        case .digit(let digit):
            footerHideTask?.cancel()
            enterDigit(digit, into: "", key: 0)
        }
    }

    enum InfoPill: Equatable {
        case audio
        case subtitle
        case restartHLS(URL, Date?)
        case searchMediathek(String)
        case settings
    }

    var availableInfoPills: [InfoPill] {
        var list: [InfoPill] = [.audio, .subtitle]
        if let entry = currentEntry, let hls = PublicHLSChannels.hlsURL(for: entry.group.key) {
            let start = player.currentProgram?.startDate
                ?? player.epgStore.currentProgram(forChannelNames: entry.group.epgNames)?.startDate
            list.append(.restartHLS(hls, start))
        }
        let title = player.currentProgram?.title ?? player.nowPlaying
        if let title, !title.isEmpty {
            list.append(.searchMediathek(title))
        }
        list.append(.settings)
        return list
    }

    func openInfoPanel() {
        cancelPendingZap()
        bannerVisible = false
        showEPGOverview = false
        overlay = .info(selection: 0)
        refreshTunerStats()
    }

    func executeInfoPill(at index: Int) {
        let pills = availableInfoPills
        guard pills.indices.contains(index) else { return }
        overlay = .info(selection: index)
        switch pills[index] {
        case .audio:
            player.cycleAudioTrack()
        case .subtitle:
            player.cycleSubtitle()
        case .restartHLS(let url, let start):
            overlay = .none
            startHLSReplay(url: url, startDate: start)
        case .searchMediathek(let title):
            overlay = .none
            searchMediathek(title: title, channel: currentEntry?.group.displayName)
        case .settings:
            overlay = .none
            showSettings = true
        }
    }

    private func handleInfo(_ command: RemoteCommand, selection: Int) {
        let pills = availableInfoPills
        let maxIndex = max(pills.count - 1, 0)
        switch command {
        case .left: overlay = .info(selection: max(selection - 1, 0))
        case .right: overlay = .info(selection: min(selection + 1, maxIndex))
        case .select:
            executeInfoPill(at: selection)
        case .back, .up, .down, .swipeUp: overlay = .none
        case .playPause: player.togglePause()
        case .digit, .pageUp, .pageDown, .swipeDown: break
        }
    }

    /// Zurück-Taste im Live-Bild: Ziel laut Einstellung.
    func openChannelList() {
        cancelPendingZap()
        bannerVisible = false
        let targetID: String
        if settings.backTarget == .epg {
            targetID = "epgOverview"
        } else if settings.backTarget == .lastChannel, let recent = recentEntries.first {
            targetID = "recent-\(recent.number)"
        } else if let current = currentEntry {
            targetID = "channel-\(current.number)"
        } else {
            targetID = "epgOverview"
        }
        overlay = .channelList(selectedID: targetID)
    }

    func openEPGOverview() {
        DebugLog.log("Programmübersicht geöffnet")
        cancelPendingZap()
        overlay = .none
        bannerTask?.cancel()
        bannerVisible = false
        epgNav.detail = nil
        epgCursorTime = nil
        let entries = epgEntries
        let preferred = playingKey ?? currentEntry.map(Self.key)
        epgSelectedKey = entries.contains { Self.key($0) == preferred } ? preferred : entries.first.map(Self.key)
        DebugLog.log("Übersicht: \(entries.count) Sender, Auswahl \(epgSelectedKey ?? "-")")
        showEPGOverview = true
        refreshInternetEPG()
    }

    func closeEPGOverview() {
        DebugLog.log("Programmübersicht geschlossen")
        epgNav.detail = nil
        showEPGOverview = false
    }

    /// Schaltet auf den Sender (Mausklick bzw. ohne Angabe die aktuelle Auswahl) und schließt die Übersicht.
    func tuneFromEPG(key: String? = nil) {
        let target = key ?? epgSelectedKey
        // Anderer Sender: Bildfläche abdecken, bevor die Übersicht schließt – sonst ist beim
        // Vergrößern kurz das letzte Bild des bisherigen Senders zu sehen.
        if let target, let entry = lineup?.entries.first(where: { Self.key($0) == target }) {
            if target != playingKey { zapFromEPG = true }
            tune(to: entry.number)
        }
        closeEPGOverview()
    }

    // MARK: Programmdaten aus dem Internet

    /// Programmdaten aller Sender kommen aus dem Internet (XMLTV): Ein Abruf weiterer Frequenzen
    /// bei der FRITZ!Box unterbräche das Live-Bild (die Box liefert einem Gerät nur einen Stream).
    private lazy var xmltvLoader = XMLTVLoader(store: player.epgStore) { [weak self] in
        self?.player.externalEPGUpdated()
    }

    func refreshInternetEPG() {
        guard let catalog else { return }
        xmltvLoader.refreshIfNeeded(channelNames: catalog.tvGroups.flatMap(\.epgNames),
                                    source: settings.xmltvSource)
    }

    func reloadInternetEPG() {
        xmltvLoader.invalidate()
        refreshInternetEPG()
    }

    // MARK: Programmübersicht: Navigation & Details

    /// Alle sichtbaren Sender der Programmübersicht.
    var epgEntries: [LineupEntry] {
        lineup?.entries ?? []
    }

    /// Sendung des gewählten Senders zur Cursorzeit (bzw. jetzt).
    private func selectedEPGProgram() -> EPGProgram? {
        guard let key = epgSelectedKey,
              let entry = lineup?.entries.first(where: { Self.key($0) == key }) else { return nil }
        let time = epgCursorTime ?? Date()
        return player.epgStore.schedule(forChannelNames: entry.group.epgNames)?.programs
            .first { $0.startDate <= time && time < $0.endDate }
    }

    private func handleEPG(_ command: RemoteCommand) {
        if let detail = epgNav.detail {
            handleEPGDetail(command, detail: detail)
            return
        }
        switch command {
        case .back:
            closeEPGOverview()
            return
        case .playPause:
            // Auf „Jetzt“: Detailtafel zur laufenden Sendung öffnen (Beschreibung, Von Anfang an, Mediathek).
            // Im Zeitstrahl verschoben: zurück zu „Jetzt“ springen.
            if epgCursorTime != nil {
                epgCursorTime = nil
            } else if let program = selectedEPGProgram(), let key = epgSelectedKey {
                epgNav.detail = EPGDetail(key: key, program: program, action: 0)
            }
            return
        case .left, .right:
            moveEPGCursor(forward: command == .right)
            return
        default:
            break
        }
        let entries = epgEntries
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex { Self.key($0) == epgSelectedKey }
        switch command {
        case .up, .down, .pageUp, .pageDown:
            let page = max(epgNav.pageSize - 1, 1)
            let step: Int
            switch command {
            case .up: step = -1
            case .down: step = 1
            case .pageUp: step = -page
            default: step = page
            }
            DebugLog.log("Übersicht: Taste \(command)")
            let next = index.map { min(max($0 + step, 0), entries.count - 1) } ?? 0
            epgSelectedKey = Self.key(entries[next])
        case .select:
            // Laufende Sendung („Jetzt“): sofort umschalten (Apple: ein Klick bis zum Bild).
            // Vergangene oder spätere Sendung im Zeitstrahl: Detailtafel mit Beschreibung und Mediathek-Suche.
            let now = Date()
            if let program = selectedEPGProgram(),
               (epgCursorTime != nil || program.endDate <= now || program.startDate > now),
               let key = epgSelectedKey {
                epgNav.detail = EPGDetail(key: key, program: program, action: 0)
            } else {
                tuneFromEPG()
            }
        case .digit(let digit):
            // Ziffer: zum Senderplatz springen (einstellige Plätze direkt)
            if let entry = lineup?.entry(number: digit) {
                epgSelectedKey = Self.key(entry)
            }
        default:
            break
        }
    }

    enum EPGDetailAction: Equatable {
        case tune
        case restartHLS(URL, Date?)
        case searchMediathek(title: String, channel: String)
        case close

        var title: String {
            switch self {
            case .tune: return "Umschalten"
            case .restartHLS: return "Von Anfang an"
            case .searchMediathek: return "In Mediathek suchen"
            case .close: return "Schließen"
            }
        }
    }

    /// Aktionen der Detailtafel: bei vergangenen Sendungen steht „In Mediathek suchen“ an erster Stelle.
    func epgDetailActions(for detail: EPGDetail) -> [EPGDetailAction] {
        let entry = lineup?.entries.first { Self.key($0) == detail.key }
        let channelName = entry?.group.displayName ?? ""
        let now = Date()
        let prog = detail.program
        let isPast = prog.endDate <= now
        let isLive = prog.startDate <= now && now < prog.endDate

        var actions: [EPGDetailAction] = []
        if isPast {
            actions.append(.searchMediathek(title: prog.title, channel: channelName))
            actions.append(.tune)
        } else {
            actions.append(.tune)
            if isLive, let groupKey = entry?.group.key, let hls = PublicHLSChannels.hlsURL(for: groupKey) {
                actions.append(.restartHLS(hls, prog.startDate))
            }
            actions.append(.searchMediathek(title: prog.title, channel: channelName))
        }
        actions.append(.close)
        return actions
    }

    func executeEPGDetailAction(_ action: EPGDetailAction, for detail: EPGDetail) {
        switch action {
        case .tune:
            epgNav.detail = nil
            tuneFromEPG(key: detail.key)
        case .restartHLS(let url, let start):
            closeEPGOverview()
            startHLSReplay(url: url, startDate: start)
        case .searchMediathek(let title, let channel):
            closeEPGOverview()
            searchMediathek(title: title, channel: channel.isEmpty ? nil : channel)
        case .close:
            epgNav.detail = nil
        }
    }

    private func handleEPGDetail(_ command: RemoteCommand, detail: EPGDetail) {
        let actions = epgDetailActions(for: detail)
        switch command {
        case .left:
            epgNav.detail?.action = max(detail.action - 1, 0)
        case .right:
            epgNav.detail?.action = min(detail.action + 1, actions.count - 1)
        case .select:
            guard actions.indices.contains(detail.action) else {
                epgNav.detail = nil
                return
            }
            executeEPGDetailAction(actions[detail.action], for: detail)
        case .back, .playPause:
            epgNav.detail = nil
        default:
            break
        }
    }

    /// Links/Rechts in der Programmübersicht: zur vorigen bzw. nächsten Sendung des gewählten
    /// Senders (bis zu 6 Stunden zurück für „Sendung verpasst“ und bis zu 22 Stunden voraus).
    /// Ohne Programmdaten in Schritten von 30 Minuten.
    private func moveEPGCursor(forward: Bool) {
        let now = Date()
        let time = epgCursorTime ?? now
        let programs: [EPGProgram]
        if let key = epgSelectedKey, let entry = lineup?.entries.first(where: { Self.key($0) == key }) {
            programs = (player.epgStore.schedule(forChannelNames: entry.group.epgNames)?.programs ?? [])
                .sorted { $0.startDate < $1.startDate }
        } else {
            programs = []
        }
        let current = programs.first { $0.startDate <= time && time < $0.endDate }
        let liveProgram = programs.first { $0.startDate <= now && now < $0.endDate }
        let target: Date
        if forward {
            target = current?.endDate
                ?? programs.first(where: { $0.startDate > time })?.startDate
                ?? Self.nextHalfHour(after: time)
            guard target < now.addingTimeInterval(22 * 3600) else { return }
        } else {
            let reference = current?.startDate ?? time
            let previous = programs.last { $0.startDate < reference && $0.endDate > reference.addingTimeInterval(-60) }
            target = previous?.startDate ?? Self.previousHalfHour(before: reference)
            guard target >= now.addingTimeInterval(-6 * 3600) else { return }
        }
        if let live = liveProgram, live.startDate <= target && target < live.endDate {
            epgCursorTime = nil
        } else if liveProgram == nil && abs(target.timeIntervalSince(now)) < 15 * 60 {
            epgCursorTime = nil
        } else {
            epgCursorTime = target
        }
    }

    /// Waagerechtes Scrollen per Maus/Trackpad in der Programmübersicht.
    func scrollEPGTime(bySeconds deltaSeconds: TimeInterval) {
        let now = Date()
        let base = epgCursorTime ?? now
        let minDate = now.addingTimeInterval(-6 * 3600)
        let maxDate = now.addingTimeInterval(22 * 3600)
        let next = min(max(base.addingTimeInterval(deltaSeconds), minDate), maxDate)
        if abs(next.timeIntervalSince(now)) < 60 {
            epgCursorTime = nil
        } else {
            epgCursorTime = next
        }
    }

    /// Nächste volle oder halbe Stunde nach `date` (Schritte ohne Programmdaten).
    private static func nextHalfHour(after date: Date) -> Date {
        let step: TimeInterval = 30 * 60
        return Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / step) + 1) * step)
    }

    private static func previousHalfHour(before date: Date) -> Date {
        let step: TimeInterval = 30 * 60
        return Date(timeIntervalSince1970: (ceil(date.timeIntervalSince1970 / step) - 1) * step)
    }

    private func handleList(_ command: RemoteCommand, selectedID: String) {
        let items = channelListItems
        guard let currentIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            overlay = .channelList(selectedID: items.first?.id ?? "epgOverview")
            return
        }
        let currentItem = items[currentIndex]

        switch command {
        case .up, .down:
            let step = command == .up ? -1 : 1
            let nextIndex = (currentIndex + step + items.count) % items.count
            overlay = .channelList(selectedID: items[nextIndex].id)
        case .select:
            switch currentItem {
            case .epgOverview:
                openEPGOverview()
            case .recent(let entry), .channel(let entry):
                overlay = .none
                tune(to: entry.number)
            case .settings:
                overlay = .none
                showSettings = true
            }
        case .pageUp, .pageDown:
            let step = command == .pageUp ? -8 : 8
            let nextIndex = min(max(currentIndex + step, 0), items.count - 1)
            overlay = .channelList(selectedID: items[nextIndex].id)
        case .playPause:
            player.togglePause()
        case .back:
            overlay = .none
        case .left, .right, .swipeUp, .swipeDown:
            break
        case .digit(let digit):
            enterDigit(digit, into: "", key: 0)
        }
    }

    func startHLSReplay(url: URL, startDate: Date?) {
        // Live-Stream ganz beenden: gibt den Tuner frei, und `resume()` startet ihn danach neu.
        player.stop()
        activeHLSReplay = (url: url, startDate: startDate)
    }

    func hlsReplayClosed() {
        activeHLSReplay = nil
        resume()
    }

    func searchMediathek(title: String, channel: String? = nil) {
        Task {
            let results = await MediathekSearchClient().search(title: title, channel: channel)
            self.searchResultDialog = (title: title, results: results)
        }
    }

    func playMediathekResult(url: URL, subtitleURL: URL? = nil) {
        activeMediathekSubtitle = subtitleURL
        player.stop()
        searchResultDialog = nil
        activeMediathekURL = url
    }

    func mediathekPlayClosed() {
        activeMediathekURL = nil
        resume()
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
        case .pageUp, .pageDown, .swipeUp, .swipeDown: break
        }
    }

    func tapDirectKey(_ keyIndex: Int) {
        guard case .directEntry(let digits, _) = overlay else { return }
        switch keyIndex {
        case 0...8: enterDigit(keyIndex + 1, into: digits, key: keyIndex)
        case 9: overlay = .directEntry(digits: String(digits.dropLast()), key: keyIndex)
        case 10: enterDigit(0, into: digits, key: keyIndex)
        default: commitDirect(digits)
        }
    }

    private func enterDigit(_ digit: Int, into digits: String, key: Int) {
        cancelPendingZap()
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
        overlay = .none
        if let number = Int(digits) {
            if lineup?.entry(number: number) != nil {
                tune(to: number)
            } else {
                player.showFeedback("Kein Sender auf Platz \(number)")
            }
        }
    }

    func directPreview(_ digits: String) -> LineupEntry? {
        Int(digits).flatMap { lineup?.entry(number: $0) }
    }

    // MARK: Senderplätze verwalten (Einstellungen)

    static func key(group: ChannelGroup) -> String { group.variants[0].groupKey }

    var allManagedChannels: [ManagedChannel] {
        guard let catalog else { return [] }
        let tv = catalog.tvGroups
        let byKey = Dictionary(tv.map { (Self.key(group: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(preferences.order)

        var items: [ManagedChannel] = []
        var currentNum = 1

        for key in preferences.order {
            guard let group = byKey[key] else { continue }
            let isHidden = preferences.hidden.contains(key)
            let num: Int? = isHidden ? nil : currentNum
            if !isHidden { currentNum += 1 }
            items.append(ManagedChannel(
                key: key,
                displayName: group.displayName,
                isHD: group.hd != nil,
                group: group,
                number: num,
                isHidden: isHidden
            ))
        }

        for group in tv where !known.contains(Self.key(group: group)) {
            let key = Self.key(group: group)
            let isHidden = preferences.hidden.contains(key)
            let num: Int? = isHidden ? nil : currentNum
            if !isHidden { currentNum += 1 }
            items.append(ManagedChannel(
                key: key,
                displayName: group.displayName,
                isHD: group.hd != nil,
                group: group,
                number: num,
                isHidden: isHidden
            ))
        }

        return items
    }

    func moveActiveChannel(key: String, by delta: Int) {
        guard let entries = lineup?.entries else { return }
        guard let currentIndex = entries.firstIndex(where: { Self.key($0) == key }) else { return }
        let targetIndex = currentIndex + delta
        guard entries.indices.contains(targetIndex) else { return }

        var activeKeys = entries.map(Self.key)
        activeKeys.swapAt(currentIndex, targetIndex)
        applyActiveOrder(activeKeys)
    }

    func moveActiveChannels(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let entries = lineup?.entries else { return }
        var activeKeys = entries.map(Self.key)
        activeKeys.move(fromOffsets: source, toOffset: destination)
        applyActiveOrder(activeKeys)
    }

    private func applyActiveOrder(_ activeKeys: [String]) {
        let activeSet = Set(activeKeys)
        var result: [String] = []
        var activeIter = activeKeys.makeIterator()
        for key in preferences.order {
            if activeSet.contains(key) {
                if let next = activeIter.next() {
                    result.append(next)
                }
            } else {
                result.append(key)
            }
        }
        while let next = activeIter.next() {
            result.append(next)
        }
        preferences.order = result
        savePreferences()
    }

    func toggleChannelVisibility(key: String) {
        if preferences.hidden.contains(key) {
            preferences.hidden.remove(key)
            savePreferences()
        } else {
            let hidesPlaying = playingKey == key
            preferences.hidden.insert(key)
            // Erst die neue Liste bauen, dann umschalten: Mit der alten Liste stünde unter
            // derselben Nummer noch der gerade ausgeblendete Sender.
            savePreferences()
            if hidesPlaying {
                tune(to: currentNumber)
            }
        }
    }

    func unhideAllChannels() {
        preferences.hidden.removeAll()
        savePreferences()
    }

    func resetLineup() {
        preferences = .standard
        savePreferences()
    }

    // MARK: Tuner-Status & Bildqualität

    func refreshTunerStats() {
        let host = boxHost
        Task { [weak self] in
            guard let self else { return }
            if let status = await FritzBoxTunerClient().fetchStatus(host: host) {
                let activeTuner = status.tuners.first(where: {
                    $0.isUsed && $0.hasLock && ($0.signalPower != nil || $0.signalNoiseRatio != nil)
                }) ?? status.tuners.first(where: \.isUsed)

                self.player.updateTunerStats(
                    signalPower: activeTuner?.signalPower,
                    snr: activeTuner?.signalNoiseRatio,
                    tunerUsage: (used: status.usedCount, total: status.totalTuners)
                )
            }
        }
    }

    // MARK: Deep Links (Top Shelf & fritztv://)

    @discardableResult
    func handleDeepLink(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "fritztv" else { return false }
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        var target: String?
        if host == "channel" {
            target = pathComponents.first
        } else if let host, !host.isEmpty {
            target = host
        } else {
            target = pathComponents.first
        }

        guard let target else { return false }

        // Senderliste noch nicht geladen (Kaltstart über das Top Shelf): nach dem Laden ausführen.
        guard loadState == .ready, let lineup else {
            pendingDeepLink = url
            return true
        }

        // Aktive Overlays oder Unterseiten schließen
        overlay = .none
        showSettings = false
        showEPGOverview = false
        activeHLSReplay = nil
        activeMediathekURL = nil
        searchResultDialog = nil

        // Top Shelf schickt zusätzlich den Senderschlüssel (`?key=…`): Er stimmt auch dann noch,
        // wenn sich die Platznummern seit dem letzten Speichern verschoben haben.
        let keyParameter = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "key" }?.value
        if let keyParameter, let entry = lineup.entries.first(where: {
            Self.key($0) == keyParameter || Channel.canonicalGroupKey(for: Self.key($0)) == Channel.canonicalGroupKey(for: keyParameter)
        }) {
            tune(to: entry.number)
            return true
        }
        if let entry = lineup.entries.first(where: {
            Self.key($0) == target || Channel.canonicalGroupKey(for: Self.key($0)) == Channel.canonicalGroupKey(for: target)
        }) {
            tune(to: entry.number)
            return true
        } else if let number = Int(target) {
            tune(to: number)
            return true
        } else if let entry = lineup.entries.first(where: {
            $0.group.key.localizedCaseInsensitiveContains(target) ||
            $0.group.displayName.localizedCaseInsensitiveContains(target)
        }) {
            tune(to: entry.number)
            return true
        }
        return false
    }
}
