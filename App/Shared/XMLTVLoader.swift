import Foundation
import FritzTVKit

/// Lädt Programmdaten aller Sender aus dem Internet (XMLTV) – ohne zweite Verbindung zur
/// FRITZ!Box, das Live-Bild läuft weiter. Die Datei wird höchstens alle 12 Stunden geladen;
/// die ausgewerteten Daten liegen zwischengespeichert vor und stehen nach dem Start sofort bereit.
@MainActor
final class XMLTVLoader {
    static let defaultSource = "https://iptv-epg.org/files/epg-de.xml"

    private let store: EPGStore
    private let onUpdate: () -> Void
    private var task: Task<Void, Never>?
    private var loadedCache = false

    private static let refreshInterval: TimeInterval = 12 * 3600
    private static let lastDownloadKey = "xmltvLastDownload"

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("epg_xmltv.json")
    }

    init(store: EPGStore, onUpdate: @escaping () -> Void) {
        self.store = store
        self.onUpdate = onUpdate
    }

    /// Lädt bei Bedarf neu. `channelNames`: alle Sendernamen der FRITZ!Box-Liste.
    func refreshIfNeeded(channelNames: [String], source: String) {
        guard task == nil else { return }
        let wanted = Set(channelNames.map(XMLTV.key))
        let last = UserDefaults.standard.object(forKey: Self.lastDownloadKey) as? Date ?? .distantPast
        let due = Date().timeIntervalSince(last) > Self.refreshInterval
        let needsCache = !loadedCache
        guard due || needsCache else { return }
        let urlString = source.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultSource : source

        task = Task { [weak self] in
            defer { self?.task = nil }
            guard let self else { return }
            if needsCache, let cached = await Self.loadCache() {
                self.store.setExternal(cached)
                self.loadedCache = true
                DebugLog.log("Programmdaten (Internet) aus Zwischenspeicher: \(cached.count) Sender")
                self.onUpdate()
            }
            guard due, let url = URL(string: urlString) else { return }
            DebugLog.log("Lade Programmdaten aus dem Internet: \(url.absoluteString)")
            let began = Date()
            guard let result = await Self.download(url: url, wanted: wanted) else {
                DebugLog.log("Programmdaten (Internet) nicht geladen")
                return
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastDownloadKey)
            self.store.setExternal(result.programsByKey)
            self.loadedCache = true
            DebugLog.log("Programmdaten (Internet): \(result.programsByKey.count) von \(result.channelCount) Sendern, \(result.programCount) Sendungen in \(Int(Date().timeIntervalSince(began))) s")
            self.onUpdate()
        }
    }

    /// Erzwingt beim nächsten `refreshIfNeeded` einen neuen Download (z. B. andere Adresse).
    func invalidate() {
        UserDefaults.standard.removeObject(forKey: Self.lastDownloadKey)
    }

    private nonisolated static func download(url: URL, wanted: Set<String>) async -> XMLTV.Result? {
        do {
            var request = URLRequest(url: url, timeoutInterval: 120)
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            let (file, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            defer { try? FileManager.default.removeItem(at: file) }
            let result = await Task.detached(priority: .utility) {
                XMLTV.parse(fileURL: file, wantedKeys: wanted)
            }.value
            if let result { await saveCache(result.programsByKey) }
            return result
        } catch {
            DebugLog.log("Programmdaten (Internet) fehlgeschlagen: \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated static func loadCache() async -> [String: [EPGProgram]]? {
        await Task.detached(priority: .utility) { () -> [String: [EPGProgram]]? in
            guard let url = cacheURL, let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [EPGProgram]].self, from: data) else { return nil }
            let cutoff = Date().addingTimeInterval(-6 * 3600)
            let pruned = decoded.mapValues { $0.filter { $0.endDate > cutoff } }.filter { !$0.value.isEmpty }
            return pruned.isEmpty ? nil : pruned
        }.value
    }

    private nonisolated static func saveCache(_ programs: [String: [EPGProgram]]) async {
        await Task.detached(priority: .background) {
            guard let url = cacheURL, let data = try? JSONEncoder().encode(programs) else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }
}
