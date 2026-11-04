import AppKit
import SwiftUI
import FritzTVKit

/// Panel unter dem Menüleistensymbol: oben der laufende Sender, darunter die Senderliste.
struct RadioPanel: View {
    @ObservedObject var model: RadioModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader(model: model)
                .padding(12)
            Divider()
            if model.showsSettings {
                RadioSettingsView(model: model) { model.showsSettings = false }
            } else {
                content
            }
            Divider()
            HStack {
                Button {
                    model.showsSettings.toggle()
                } label: {
                    Image(systemName: model.showsSettings ? "list.bullet" : "gearshape")
                }
                .help(model.showsSettings ? "Senderliste" : "Einstellungen (⌘,)")
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Lade Senderliste …")
                .frame(maxWidth: .infinity, minHeight: 400)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Erneut versuchen") { Task { await model.load() } }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 400)
        case .ready:
            VStack(spacing: 0) {
                TextField("Sender suchen", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    // Return spielt den ersten Treffer, Esc leert die Suche.
                    .onSubmit(model.playFirstHit)
                    .onExitCommand { model.searchText = "" }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                StationList(model: model)
                    .frame(height: 360)
            }
        }
    }
}

// MARK: Laufender Sender

private struct NowPlayingHeader: View {
    @ObservedObject var model: RadioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let station = model.current {
                HStack(alignment: .top, spacing: 12) {
                    RadioLogoView(name: station.displayName, width: 96, height: 60) {
                        model.updateNowPlaying()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        programInfo(for: station)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Sender auswählen")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let line = statusLine {
                Text(line.text)
                    .font(.caption)
                    .foregroundStyle(line.isProblem ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
        }
    }

    @ViewBuilder
    private func programInfo(for station: ChannelGroup) -> some View {
        if let program = model.currentProgram(of: station) {
            Text(program.title)
                .font(.subheadline)
                .lineLimit(2)
            Text("\(Self.time.string(from: program.startDate)) – \(Self.time.string(from: program.endDate))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let next = model.nextProgram(of: station) {
            Text("Ab \(Self.time.string(from: next.startDate)): \(next.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var statusLine: (text: String, isProblem: Bool)? {
        if let problem = model.problem { return (problem, true) }
        if model.isPlaying, model.player.status == .connecting { return ("Verbinde …", false) }
        return nil
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { model.step(-1) } label: { Image(systemName: "backward.fill") }
                .help("Voriger Sender")
                .disabled(model.current == nil)
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 24)
            }
            .help(model.isPlaying ? "Anhalten (gibt den Tuner frei)" : "Abspielen")
            .disabled(model.loadState != .ready)
            Button { model.step(+1) } label: { Image(systemName: "forward.fill") }
                .help("Nächster Sender")
                .disabled(model.current == nil)
            Spacer()
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(model.volume) }, set: { model.volume = Int($0) }), in: 0...100)
                .frame(width: 110)
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: Senderliste

private struct StationList: View {
    @ObservedObject var model: RadioModel

    var body: some View {
        let sections = model.sections
        if sections.isEmpty {
            Text("Kein Sender gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.stations, id: \.key) { station in
                                    StationRow(station: station,
                                               isCurrent: station == model.current,
                                               isPlaying: station == model.current && model.isPlaying,
                                               isFavorite: model.isFavorite(station),
                                               isDead: model.isDead(station),
                                               play: { model.play(station) },
                                               toggleFavorite: { model.toggleFavorite(station) })
                                        // Ein Sender steht ggf. mehrfach (Favoriten, Zuletzt gehört, Familie):
                                        // Die Kennung muss trotzdem in der ganzen Liste eindeutig sein.
                                        .id(Self.rowID(section: section, station: station))
                                }
                            } header: {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.bar)
                            }
                        }
                    }
                }
                // Beim Öffnen steht der laufende Sender im Blick, wenn er nicht oben in Favoriten/Zuletzt steht.
                .onAppear {
                    guard let current = model.current, model.searchText.isEmpty,
                          let first = sections.first(where: { $0.stations.contains(current) }),
                          !["favorites", "recent"].contains(first.id)
                    else { return }
                    proxy.scrollTo(Self.rowID(section: first, station: current), anchor: .center)
                }
            }
        }
    }
}

extension StationList {
    static func rowID(section: RadioListSection, station: ChannelGroup) -> String {
        "\(section.id)/\(station.key)"
    }
}

private struct StationRow: View {
    let station: ChannelGroup
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let isDead: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RadioLogoView(name: station.displayName, width: 44, height: 28)
            Text(station.displayName)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isFavorite || hovering ? 1 : 0)
            .help(isFavorite ? "Aus den Favoriten entfernen" : "Zu den Favoriten")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .opacity(isDead ? 0.5 : 1)
        .background(hovering ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: play)
        .contextMenu {
            Button("Abspielen", action: play)
            Button(isFavorite ? "Aus den Favoriten entfernen" : "Zu den Favoriten", action: toggleFavorite)
        }
        .help(isDead ? "Lieferte zuletzt keinen Ton" : "")
    }
}

// MARK: Einstellungen

private struct RadioSettingsView: View {
    @ObservedObject var model: RadioModel
    let done: () -> Void
    @State private var host = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Adresse der FRITZ!Box")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    TextField("automatisch (fritz.box)", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connect)
                    Button("Verbinden", action: connect)
                }
                Text("Leer lassen, um die Box im Heimnetz selbst zu finden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Beim Anmelden starten", isOn: Binding(get: { model.launchesAtLogin },
                                                         set: { model.launchesAtLogin = $0 }))
            VStack(alignment: .leading, spacing: 6) {
                Button("Sender ohne Empfang wieder freigeben", action: model.resetDeadStations)
                    .disabled(model.deadIDs.isEmpty)
                Text("Nach einem Sendersuchlauf der FRITZ!Box sinnvoll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Text("FritzRadio \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fertig", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(height: 408, alignment: .top)
        .onAppear { host = model.host }
    }

    private func connect() {
        model.host = host.trimmingCharacters(in: .whitespaces)
        Task { await model.load() }
        done()
    }
}
