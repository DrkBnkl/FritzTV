import SwiftUI
import FritzTVKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var focusedIndex: Int = 0
    @State private var showChannelManager = false
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    enum SettingsRow: Int, CaseIterable {
        case channelManager = 0
        case reloadList = 1
        case networkCaching = 2
        case rtspTCP = 3
        case preferHD = 4
        case deinterlaceSD = 5
        case timeshift = 6
        case audioDelay = 7
        case bannerSeconds = 8
    }

    private let cachingValues = [500, 1000, 2000, 3000, 5000]
    private let delayValues = Array(stride(from: -500, through: 500, by: 25))
    private let bannerValues = [8, 10, 15, 20, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sendersortierung") {
                    NavigationLink(destination: ChannelManagerView(model: model), isActive: $showChannelManager) {
                        HStack {
                            Label("Sender sortieren & ausblenden", systemImage: "list.number")
                            Spacer()
                            Text("\(model.lineup?.entries.count ?? 0) aktiv · \(model.lineup?.hiddenGroups.count ?? 0) ausgeblendet")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.channelManager.rawValue))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedIndex = SettingsRow.channelManager.rawValue
                        showChannelManager = true
                    }

                    if !settings.deadChannelIDs.isEmpty {
                        Button("Geprüfte Sender zurücksetzen (\(settings.deadChannelIDs.count) gemerkt)") {
                            settings.resetDeadVariants()
                        }
                    }
                }

                Section {
                    TextField("FRITZ!Box-Adresse (leer = automatisch)", text: $settings.host)
                    LabeledContent("Verbunden mit", value: model.connectedHost ?? "–")
                    Button("Senderliste neu laden") {
                        Task { await model.load() }
                    }
                    .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.reloadList.rawValue))
                    .contentShape(Rectangle())
                    .onTapGesture { focusedIndex = SettingsRow.reloadList.rawValue }

                    Picker("Netzwerkpuffer", selection: $settings.networkCaching) {
                        Text("Automatisch").tag(0)
                        ForEach(cachingValues, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                    .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.networkCaching.rawValue))
                    .contentShape(Rectangle())
                    .onTapGesture { focusedIndex = SettingsRow.networkCaching.rawValue }

                    Toggle("RTP über TCP", isOn: $settings.rtspTCP)
                        .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.rtspTCP.rawValue))
                        .contentShape(Rectangle())
                        .onTapGesture { focusedIndex = SettingsRow.rtspTCP.rawValue }
                } header: {
                    Text("Verbindung")
                } footer: {
                    Text("Eine geänderte Adresse gilt nach „Senderliste neu laden“. Über VPN aus dem Hotel: Netzwerkpuffer 3000 ms wählen. Bricht das Bild immer wieder ab, „RTP über TCP“ probieren.")
                }

                StationSearchSection(model: model, settings: settings, search: model.stationSearch)

                Section("Wiedergabe") {
                    Toggle("HD bevorzugen", isOn: $settings.preferHD)
                        .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.preferHD.rawValue))
                        .contentShape(Rectangle())
                        .onTapGesture { focusedIndex = SettingsRow.preferHD.rawValue }

                    Toggle("Deinterlacing für SD-Sender", isOn: $settings.deinterlaceSD)
                        .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.deinterlaceSD.rawValue))
                        .contentShape(Rectangle())
                        .onTapGesture { focusedIndex = SettingsRow.deinterlaceSD.rawValue }

                    Toggle("Timeshift (Live-Bild anhalten)", isOn: $settings.timeshift)
                        .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.timeshift.rawValue))
                        .contentShape(Rectangle())
                        .onTapGesture { focusedIndex = SettingsRow.timeshift.rawValue }

                    #if os(tvOS)
                    Toggle("Bildwiederholrate auf 50 Hz", isOn: $settings.match50Hz)
                    #endif

                    Picker("Tonverzögerung", selection: $settings.audioDelayMs) {
                        ForEach(delayValues, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                    .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.audioDelay.rawValue))
                    .contentShape(Rectangle())
                    .onTapGesture { focusedIndex = SettingsRow.audioDelay.rawValue }

                    Picker("Sendungsinfo einblenden", selection: $settings.bannerSeconds) {
                        ForEach(bannerValues, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .modifier(CursorRowHighlight(selected: focusedIndex == SettingsRow.bannerSeconds.rawValue))
                    .contentShape(Rectangle())
                    .onTapGesture { focusedIndex = SettingsRow.bannerSeconds.rawValue }
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
            #if os(macOS)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("↑/↓: Zeile wählen · ←/→: Wert ändern · Leertaste/Return: umschalten · Esc: Fertig")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 620, maxWidth: .infinity, minHeight: 400, idealHeight: 560, maxHeight: .infinity)
        .onAppear { setupKeyMonitor() }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        #endif
    }

    #if os(macOS)
    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape: Fertig / Schließen
            if event.keyCode == 53 {
                dismiss()
                return nil
            }
            // Up Arrow
            if event.keyCode == 126 {
                moveFocus(-1)
                return nil
            }
            // Down Arrow
            if event.keyCode == 125 {
                moveFocus(1)
                return nil
            }
            // Left Arrow
            if event.keyCode == 123 {
                adjustSetting(delta: -1)
                return nil
            }
            // Right Arrow
            if event.keyCode == 124 {
                adjustSetting(delta: 1)
                return nil
            }
            // Space / Return / Enter
            if event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 {
                activateSetting()
                return nil
            }
            return event
        }
    }
    #endif

    private func moveFocus(_ step: Int) {
        let count = SettingsRow.allCases.count
        focusedIndex = (focusedIndex + step + count) % count
    }

    private func adjustSetting(delta: Int) {
        guard let row = SettingsRow(rawValue: focusedIndex) else { return }
        switch row {
        case .channelManager, .reloadList:
            break
        case .networkCaching:
            let all = [0] + cachingValues
            if let idx = all.firstIndex(of: settings.networkCaching) {
                let nextIdx = min(max(idx + delta, 0), all.count - 1)
                settings.networkCaching = all[nextIdx]
            }
        case .rtspTCP:
            settings.rtspTCP = (delta > 0)
        case .preferHD:
            settings.preferHD = (delta > 0)
        case .deinterlaceSD:
            settings.deinterlaceSD = (delta > 0)
        case .timeshift:
            settings.timeshift = (delta > 0)
        case .audioDelay:
            let next = min(max(settings.audioDelayMs + delta * 25, -500), 500)
            settings.audioDelayMs = next
        case .bannerSeconds:
            if let idx = bannerValues.firstIndex(of: settings.bannerSeconds) {
                let nextIdx = min(max(idx + delta, 0), bannerValues.count - 1)
                settings.bannerSeconds = bannerValues[nextIdx]
            }
        }
    }

    private func activateSetting() {
        guard let row = SettingsRow(rawValue: focusedIndex) else { return }
        switch row {
        case .channelManager:
            showChannelManager = true
        case .reloadList:
            Task { await model.load() }
        case .networkCaching:
            adjustSetting(delta: 1)
        case .rtspTCP:
            settings.rtspTCP.toggle()
        case .preferHD:
            settings.preferHD.toggle()
        case .deinterlaceSD:
            settings.deinterlaceSD.toggle()
        case .timeshift:
            settings.timeshift.toggle()
        case .audioDelay:
            break
        case .bannerSeconds:
            adjustSetting(delta: 1)
        }
    }
}

private struct CursorRowHighlight: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
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

/// Übersicht aller Sender zum Sortieren (per Drag-and-Drop oder Pfeil-Tasten) und Ein-/Ausblenden.
struct ChannelManagerView: View {
    @ObservedObject var model: AppModel
    @State private var filter: Filter = .all
    @State private var searchText = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case active = "Aktiv"
        case hidden = "Ausgeblendet"
        var id: String { rawValue }
    }

    private var allChannels: [ManagedChannel] {
        model.allManagedChannels
    }

    private var filteredChannels: [ManagedChannel] {
        allChannels.filter { channel in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .active: matchesFilter = !channel.isHidden
            case .hidden: matchesFilter = channel.isHidden
            }
            guard matchesFilter else { return false }
            if searchText.isEmpty { return true }
            return channel.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    let count = count(for: f)
                    Text("\(f.rawValue) (\(count))").tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                if filteredChannels.isEmpty {
                    Text("Keine Sender gefunden")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(filteredChannels) { channel in
                        channelRow(channel)
                    }
                    .onMove(perform: (filter == .active && searchText.isEmpty) ? moveChannels : nil)
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
        }
        .navigationTitle("Sender verwalten")
        .searchable(text: $searchText, prompt: "Sender suchen…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Standardbelegung wiederherstellen") {
                        model.resetLineup()
                    }
                    Button("Alle Sender einblenden") {
                        model.unhideAllChannels()
                    }
                } label: {
                    Label("Aktionen", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func count(for f: Filter) -> Int {
        switch f {
        case .all: return allChannels.count
        case .active: return model.lineup?.entries.count ?? 0
        case .hidden: return model.lineup?.hiddenGroups.count ?? 0
        }
    }

    private func channelRow(_ channel: ManagedChannel) -> some View {
        HStack(spacing: 12) {
            // Platznummer
            if let num = channel.number {
                Text("\(num)")
                    .font(.system(.body, design: .monospaced).bold())
                    .frame(width: 36, alignment: .trailing)
                    .foregroundStyle(.primary)
            } else {
                Text("–")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
                    .foregroundStyle(.tertiary)
            }

            // Senderlogo
            ChannelLogoView(channelName: channel.displayName, height: 24, maxWidth: 54)

            // Sendername & HD
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(channel.displayName)
                        .font(.body.weight(channel.isHidden ? .regular : .semibold))
                        .foregroundStyle(channel.isHidden ? .secondary : .primary)
                    if channel.isHD {
                        Text("HD")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.18))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            // Reorder-Tasten (nur bei aktiven Sendern)
            if !channel.isHidden {
                HStack(spacing: 4) {
                    Button {
                        model.moveActiveChannel(key: channel.key, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(channel.number == 1)
                    .help("Nach oben schieben")

                    Button {
                        model.moveActiveChannel(key: channel.key, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(channel.number == (model.lineup?.entries.count ?? 0))
                    .help("Nach unten schieben")
                }
            }

            // Sichtbarkeit-Schalter
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.toggleChannelVisibility(key: channel.key)
                }
            } label: {
                Label(
                    channel.isHidden ? "Einblenden" : "Ausblenden",
                    systemImage: channel.isHidden ? "eye.slash" : "eye"
                )
                .labelStyle(.iconOnly)
                .foregroundStyle(channel.isHidden ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(channel.isHidden ? "Sender einblenden" : "Sender ausblenden")
        }
        .padding(.vertical, 4)
    }

    private func moveChannels(from source: IndexSet, to destination: Int) {
        model.moveActiveChannels(fromOffsets: source, toOffset: destination)
    }
}
