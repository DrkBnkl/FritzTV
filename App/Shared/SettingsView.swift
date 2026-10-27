import SwiftUI
import FritzTVKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var focusedIndex: Int = 0
    @State private var showChannelManager = false
    /// Gleicher Schlüssel wie im Mediathek-Player.
    @AppStorage("mediathekSubtitles") private var mediathekSubtitles = false
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    /// Zeilen für die Tastatursteuerung auf dem Mac (Reihenfolge = Reihenfolge auf dem Bildschirm).
    enum SettingsRow: Int, CaseIterable {
        case backTarget = 0
        case bannerSeconds = 1
        case channelManager = 2
        case reloadList = 3
        case networkCaching = 4
        case rtspTCP = 5
        case preferHD = 6
        case deinterlaceSD = 7
        case blackScreenOnZap = 8
        case timeshift = 9
        case timeshiftMinutes = 10
        case audioDelay = 11
        case audioDelayAC3 = 12
    }

    private let cachingValues = [500, 1000, 2000, 3000, 5000]
    private let delayValues = Array(stride(from: -500, through: 500, by: 25))
    private let bannerValues = [5, 7, 10, 15, 20, 30]
    private let timeshiftMinuteValues = [30, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bedienung") {
                    OptionRow(title: "Zurück-Taste (\(UI.back)) öffnet", selection: $settings.backTarget,
                              options: BackTarget.allCases) { $0.title }
                    .cursorRow(.backTarget, focusedIndex: $focusedIndex)

                    OptionRow(title: "Sendungsinfo einblenden", selection: $settings.bannerSeconds,
                              options: bannerValues) { "\($0) s" }
                    .cursorRow(.bannerSeconds, focusedIndex: $focusedIndex)
                }

                Section("Sendersortierung") {
                    NavigationLink(destination: ChannelManagerView(model: model).settingsPageBackground(),
                                   isActive: $showChannelManager) {
                        HStack {
                            Label("Sender sortieren & ausblenden", systemImage: "list.number")
                            Spacer()
                            Text("\(model.lineup?.entries.count ?? 0) aktiv · \(model.lineup?.hiddenGroups.count ?? 0) ausgeblendet")
                                #if os(macOS)
                                .foregroundStyle(.secondary)
                                #endif
                        }
                    }
                    .cursorRow(.channelManager, focusedIndex: $focusedIndex) {
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
                    .cursorRow(.reloadList, focusedIndex: $focusedIndex)

                    OptionRow(title: "Netzwerkpuffer", selection: $settings.networkCaching,
                              options: [0] + cachingValues) { $0 == 0 ? "Automatisch" : "\($0) ms" }
                    .cursorRow(.networkCaching, focusedIndex: $focusedIndex)

                    Toggle("RTP über TCP", isOn: $settings.rtspTCP)
                        .cursorRow(.rtspTCP, focusedIndex: $focusedIndex)
                } header: {
                    Text("Verbindung")
                } footer: {
                    Text("Eine geänderte Adresse gilt nach „Senderliste neu laden“. Über VPN aus dem Hotel: Netzwerkpuffer 3000 ms wählen. Bricht das Bild immer wieder ab, „RTP über TCP“ probieren.")
                }

                StationSearchSection(model: model, settings: settings, search: model.stationSearch)

                Section("Wiedergabe") {
                    Toggle("HD bevorzugen", isOn: $settings.preferHD)
                        .cursorRow(.preferHD, focusedIndex: $focusedIndex)

                    Toggle("Deinterlacing für SD-Sender", isOn: $settings.deinterlaceSD)
                        .cursorRow(.deinterlaceSD, focusedIndex: $focusedIndex)

                    Toggle("Schwarzer Bildschirm beim Umschalten", isOn: $settings.blackScreenOnZap)
                        .cursorRow(.blackScreenOnZap, focusedIndex: $focusedIndex)

                    Toggle("Timeshift (Live-Bild anhalten)", isOn: $settings.timeshift)
                        .cursorRow(.timeshift, focusedIndex: $focusedIndex)

                    OptionRow(title: "Timeshift-Puffer", selection: $settings.timeshiftMinutes,
                              options: timeshiftMinuteValues) { "\($0) Min." }
                    .disabled(!settings.timeshift)
                    .cursorRow(.timeshiftMinutes, focusedIndex: $focusedIndex)

                    #if os(tvOS)
                    Toggle("Bildwiederholrate auf 50 Hz", isOn: $settings.match50Hz)
                    #endif

                    OptionRow(title: "Tonverzögerung Stereo", selection: $settings.audioDelayMs,
                              options: delayValues) { "\($0) ms" }
                    .cursorRow(.audioDelay, focusedIndex: $focusedIndex)

                    OptionRow(title: "Tonverzögerung Dolby Digital (AC3)", selection: $settings.audioDelayAC3Ms,
                              options: delayValues) { "\($0) ms" }
                    .cursorRow(.audioDelayAC3, focusedIndex: $focusedIndex)
                }

                Section {
                    TextField("Adresse (leer = \(XMLTVLoader.defaultSource))", text: $settings.xmltvSource)
                        .autocorrectionDisabled()
                    Button("Programmdaten jetzt neu laden") {
                        model.reloadInternetEPG()
                    }
                } header: {
                    Text("Programmdaten")
                } footer: {
                    Text("Die Programmdaten aller Sender kommen aus dem Internet (XMLTV, alle 12 Stunden). Für den laufenden Sender zeigt die App die genaueren Daten aus dem Fernsehsignal.")
                }

                Section {
                    TextField("press2arr-Adresse (z. B. 192.168.178.99:5056)", text: $settings.press2arrAddress)
                        .autocorrectionDisabled()
                    Toggle("Untertitel bei Mediathek-Videos", isOn: $mediathekSubtitles)
                } header: {
                    Text("Mediathek")
                } footer: {
                    Text("Die Spielfilm-Übersicht kommt von press2arr („Lichtspiel“) auf der NAS. Untertitel gibt es, wenn der Sender welche anbietet.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .settingsPageBackground()
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
        // Deckender Hintergrund: Sonst scheint das Fernsehbild stark durch und die Einträge
        // sind kaum lesbar.
        .settingsPageBackground()
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
        case .blackScreenOnZap:
            settings.blackScreenOnZap = (delta > 0)
        case .timeshift:
            settings.timeshift = (delta > 0)
        case .timeshiftMinutes:
            settings.timeshiftMinutes = Self.step(timeshiftMinuteValues, from: settings.timeshiftMinutes, by: delta)
        case .audioDelay:
            let next = min(max(settings.audioDelayMs + delta * 25, -500), 500)
            settings.audioDelayMs = next
        case .audioDelayAC3:
            let next = min(max(settings.audioDelayAC3Ms + delta * 25, -500), 500)
            settings.audioDelayAC3Ms = next
        case .bannerSeconds:
            settings.bannerSeconds = Self.step(bannerValues, from: settings.bannerSeconds, by: delta)
        case .backTarget:
            let all = BackTarget.allCases
            let index = all.firstIndex(of: settings.backTarget) ?? 0
            settings.backTarget = all[min(max(index + delta, 0), all.count - 1)]
        }
    }

    /// Nächster Wert einer Auswahlliste; ein Wert außerhalb der Liste springt zum nächstgelegenen.
    private static func step(_ values: [Int], from current: Int, by delta: Int) -> Int {
        guard !values.isEmpty else { return current }
        let index = values.firstIndex(of: current)
            ?? values.indices.min { abs(values[$0] - current) < abs(values[$1] - current) } ?? 0
        return values[min(max(index + delta, 0), values.count - 1)]
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
        case .blackScreenOnZap:
            settings.blackScreenOnZap.toggle()
        case .timeshift:
            settings.timeshift.toggle()
        case .timeshiftMinutes:
            adjustSetting(delta: 1)
        case .audioDelay, .audioDelayAC3:
            break
        case .bannerSeconds:
            adjustSetting(delta: 1)
        case .backTarget:
            let all = BackTarget.allCases
            let index = all.firstIndex(of: settings.backTarget) ?? 0
            settings.backTarget = all[(index + 1) % all.count]
        }
    }
}

private extension View {
    /// Mac: Rahmen für die Tastatursteuerung und Klick zum Auswählen. Apple TV: nichts – dort
    /// übernimmt der System-Fokus die Hervorhebung. (Rahmen und Klick-Geste lagen auf dem
    /// Apple TV über der Fokus-Hervorhebung und machten die Schrift schwer lesbar.)
    func cursorRow(_ row: SettingsView.SettingsRow, focusedIndex: Binding<Int>,
                   onSelect: (() -> Void)? = nil) -> some View {
        #if os(macOS)
        return self
            .modifier(CursorRowHighlight(selected: focusedIndex.wrappedValue == row.rawValue))
            .contentShape(Rectangle())
            .onTapGesture {
                focusedIndex.wrappedValue = row.rawValue
                onSelect?()
            }
        #else
        return self
        #endif
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

// MARK: - Auswahlzeilen

/// Einstellung mit festen Werten. Auf dem Apple TV eine Zeile, die eine eigene Auswahlseite
/// öffnet; auf dem Mac ein normales Aufklapp-Menü.
///
/// Ersetzt auf dem Apple TV den System-Picker: Dessen Menü und auch dessen Auswahlseite
/// (`.navigationLink`) erschienen im Vollbild-Cover leer und durchsichtig und ließen sich
/// nicht bedienen.
struct OptionRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    init(title: String, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        #if os(tvOS)
        NavigationLink {
            OptionListView(title: title, selection: $selection, options: options, label: label)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(label(selection))
            }
        }
        #else
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        #endif
    }
}

#if os(tvOS)
/// Auswahlseite: Klick übernimmt den Wert und führt zurück zu den Einstellungen.
private struct OptionListView<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Value?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack {
                            Text(label(option))
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .focused($focused, equals: option)
                    .id(option)
                }
            }
            .onAppear {
                // Fokus und Sichtbereich auf den aktuellen Wert (wichtig bei langen Listen
                // wie der Tonverzögerung).
                proxy.scrollTo(selection, anchor: .center)
                DispatchQueue.main.async { focused = selection }
            }
        }
        .navigationTitle(title)
        .settingsPageBackground()
    }
}
#endif

extension View {
    /// Deckender, dunkler Hintergrund für die Einstellungsseiten auf dem Apple TV. Ohne ihn
    /// scheint das Fernsehbild durch das Vollbild-Cover und die Unterseiten.
    @ViewBuilder func settingsPageBackground() -> some View {
        #if os(tvOS)
        self
            .background(Color(red: 0.06, green: 0.07, blue: 0.09).ignoresSafeArea())
            .presentationBackground(Color(red: 0.06, green: 0.07, blue: 0.09))
        #else
        self
        #endif
    }
}
