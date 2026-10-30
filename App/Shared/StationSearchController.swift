import Foundation
import Security
import FritzTVKit

/// Kennwort der FRITZ!Box im Schlüsselbund (nicht in den UserDefaults).
enum BoxPasswordStore {
    private static let service = "de.home.fritztv.box"
    private static let account = "tr064"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        #if os(macOS)
        // Migration: Falls das Kennwort zuvor ohne uneingeschränkte SecAccess-ACL gespeichert war,
        // einmalig neu speichern, damit bei künftigen Zugriffen keine Abfrage mehr erfolgt.
        _ = save(password)
        #endif
        return password
    }

    @discardableResult
    static func save(_ password: String) -> Bool {
        delete()
        guard !password.isEmpty else { return true }
        #if os(macOS)
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8)
        ]
        if let access = CreateUnrestrictedKeychainAccess("FRITZ!Box") {
            attributes[kSecAttrAccess as String] = access
        }
        #else
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(password.utf8)
        ]
        #endif
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasPassword: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

/// Ablauf des Sendersuchlaufs aus der App: Fernsehbild stoppen (der Suchlauf braucht die Tuner),
/// Suchlauf starten, Fortschritt abfragen, danach Senderliste neu laden und die Liste
/// der toten Varianten zurücksetzen.
@MainActor
final class StationSearchController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case credentialsOK
        case running(progress: Int)
        case reloading
        case finished(channelCount: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .checking, .running, .reloading: return true
        default: return false
        }
    }

    private func client(model: AppModel) -> FritzBoxStationSearch? {
        guard let password = BoxPasswordStore.load(), !password.isEmpty else { return nil }
        return FritzBoxStationSearch(host: model.boxHost, username: model.settings.boxUsername, password: password)
    }

    /// Prüft nur die Anmeldung, ohne etwas an der Box zu ändern.
    func verify(model: AppModel) {
        guard let client = client(model: model) else {
            phase = .failed("Bitte zuerst das Kennwort der FRITZ!Box eingeben.")
            return
        }
        task?.cancel()
        phase = .checking
        task = Task {
            do {
                try await client.verifyCredentials()
                phase = .credentialsOK
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func start(model: AppModel) {
        guard let client = client(model: model) else {
            phase = .failed("Bitte zuerst das Kennwort der FRITZ!Box eingeben.")
            return
        }
        task?.cancel()
        phase = .checking
        task = Task {
            do {
                try await client.verifyCredentials()
                model.player.stop()
                DebugLog.log("Sendersuchlauf: Start")
                var status = try await client.start()
                phase = .running(progress: status.progress)

                // Läuft der Suchlauf? Die Box braucht einen Moment, bis sie „active“ meldet.
                var sawActive = status.isActive
                let started = Date()
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    status = try await client.status()
                    if status.isActive {
                        sawActive = true
                        phase = .running(progress: status.progress)
                    } else if sawActive || status.progress >= 100 {
                        break
                    } else if Date().timeIntervalSince(started) > 20 {
                        throw StationSearchError.boxError("Der Suchlauf wurde nicht gestartet.")
                    }
                    if Date().timeIntervalSince(started) > 30 * 60 {
                        throw StationSearchError.boxError("Der Suchlauf dauert ungewöhnlich lange.")
                    }
                }
                if Task.isCancelled { return }

                DebugLog.log("Sendersuchlauf: fertig, lade Senderliste")
                phase = .reloading
                model.settings.resetDeadVariants()
                await model.load()
                phase = .finished(channelCount: model.lineup?.entries.count ?? 0)
            } catch is CancellationError {
                return
            } catch {
                DebugLog.log("Sendersuchlauf fehlgeschlagen: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
                model.resume()
            }
        }
    }

    func cancel(model: AppModel) {
        task?.cancel()
        task = nil
        let client = client(model: model)
        phase = .idle
        Task {
            try? await client?.stop()
            DebugLog.log("Sendersuchlauf abgebrochen")
            await model.load()
        }
    }
}
