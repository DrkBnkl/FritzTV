import SwiftUI
import FritzTVKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let cachingValues = [500, 1000, 2000, 3000, 5000]
    private let delayValues = Array(stride(from: -500, through: 500, by: 25))
    private let bannerValues = [3, 5, 7, 10, 15]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("FRITZ!Box-Adresse (leer = automatisch)", text: $settings.host)
                    LabeledContent("Verbunden mit", value: model.connectedHost ?? "–")
                    Button("Senderliste neu laden") {
                        Task { await model.load() }
                    }
                    Picker("Netzwerkpuffer", selection: $settings.networkCaching) {
                        Text("Automatisch").tag(0)
                        ForEach(cachingValues, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                    Toggle("RTP über TCP", isOn: $settings.rtspTCP)
                } header: {
                    Text("Verbindung")
                } footer: {
                    Text("Eine geänderte Adresse gilt nach „Senderliste neu laden“. Über VPN aus dem Hotel: Netzwerkpuffer 3000 ms wählen. Bricht das Bild immer wieder ab, „RTP über TCP“ probieren.")
                }

                StationSearchSection(model: model, settings: settings, search: model.stationSearch)

                Section {
                    TextField("press2arr-Adresse", text: $settings.press2arrAddress)
                } header: {
                    Text("Mediathek")
                } footer: {
                    Text("Adresse von press2arr („Lichtspiel“) auf der NAS, z. B. 192.168.178.99:5056. Zu finden in der Senderliste ganz oben unter „Mediathek“.")
                }

                Section("Wiedergabe") {
                    Toggle("HD bevorzugen", isOn: $settings.preferHD)
                    Toggle("Deinterlacing für SD-Sender", isOn: $settings.deinterlaceSD)
                    Toggle("Timeshift (Live-Bild anhalten)", isOn: $settings.timeshift)
                    #if os(tvOS)
                    Toggle("Bildwiederholrate auf 50 Hz", isOn: $settings.match50Hz)
                    #endif
                    Picker("Tonverzögerung", selection: $settings.audioDelayMs) {
                        ForEach(delayValues, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                    Picker("Sendungsinfo einblenden", selection: $settings.bannerSeconds) {
                        ForEach(bannerValues, id: \.self) { Text("\($0) s").tag($0) }
                    }
                }

                Section {
                    Button("Aktuellen Sender ausblenden") { model.hideCurrentChannel() }
                    Button("Standardbelegung wiederherstellen") { model.resetLineup() }
                    if !settings.deadChannelIDs.isEmpty {
                        Button("Geprüfte Sender zurücksetzen (\(settings.deadChannelIDs.count) gemerkt)") {
                            settings.resetDeadVariants()
                        }
                    }
                    ForEach(model.lineup?.hiddenGroups ?? []) { group in
                        Button("\(group.displayName) einblenden") { model.unhide(group) }
                    }
                } header: {
                    Text("Senderplätze")
                } footer: {
                    Text("Verschieben: in der Senderliste den Sender auswählen, \(UI.playPause) drücken, mit \(UI.upDown) an den neuen Platz bringen.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Fertig") { dismiss() }
                    #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                    #endif
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 680)
        #endif
    }
}

/// Sendersuchlauf der FRITZ!Box aus der App (TR-064, braucht Box-Zugangsdaten).
private struct StationSearchSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var search: StationSearchController
    @State private var password = ""
    @State private var hasStoredPassword = BoxPasswordStore.hasPassword

    var body: some View {
        Section {
            TextField("Benutzername der FRITZ!Box", text: $settings.boxUsername)
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField(hasStoredPassword ? "Kennwort (gespeichert)" : "Kennwort der FRITZ!Box", text: $password)
                .textContentType(.password)
                .onSubmit(savePassword)
            if !password.isEmpty {
                Button("Kennwort speichern", action: savePassword)
            }
            if hasStoredPassword {
                Button("Zugangsdaten prüfen") { search.verify(model: model) }
                    .disabled(search.isRunning)
                if search.isRunning, case .running = search.phase {
                    Button("Suchlauf abbrechen", role: .destructive) { search.cancel(model: model) }
                } else {
                    Button("Sendersuchlauf starten") { search.start(model: model) }
                        .disabled(search.isRunning)
                }
                Button("Kennwort löschen", role: .destructive) {
                    BoxPasswordStore.delete()
                    hasStoredPassword = false
                }
                .disabled(search.isRunning)
            }
            statusRow
        } header: {
            Text("Sendersuchlauf")
        } footer: {
            Text("Startet den DVB-C-Sendersuchlauf der FRITZ!Box, z. B. wenn Sender nach einer Frequenzumstellung kein Bild mehr haben. Braucht einen Benutzer der FRITZ!Box mit der Berechtigung „FRITZ!Box Einstellungen“. Das Kennwort bleibt im Schlüsselbund dieses Geräts. Während des Suchlaufs (einige Minuten) gibt es kein Fernsehbild; danach wird die Senderliste neu geladen, die Senderplätze bleiben erhalten.")
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch search.phase {
        case .idle:
            EmptyView()
        case .checking:
            LabeledContent("Status", value: "Verbinde mit der FRITZ!Box …")
        case .credentialsOK:
            LabeledContent("Status", value: "Anmeldung in Ordnung")
        case .running(let progress):
            VStack(alignment: .leading) {
                Text("Suchlauf läuft … \(progress) %")
                ProgressView(value: Double(progress), total: 100)
            }
        case .reloading:
            LabeledContent("Status", value: "Lade Senderliste …")
        case .finished(let count):
            LabeledContent("Status", value: "Fertig – \(count) Senderplätze")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private func savePassword() {
        guard !password.isEmpty else { return }
        hasStoredPassword = BoxPasswordStore.save(password)
        password = ""
    }
}
