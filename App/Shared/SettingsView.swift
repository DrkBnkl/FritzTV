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
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 680)
        #endif
    }
}
