import SwiftUI
import FritzTVKit
#if os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: Senderlogo

/// Geladene Radiologos. Beim Blättern erscheinen dieselben Zeilen immer wieder; ohne eigenen Speicher
/// würde jedes Logo dabei kurz verschwinden und neu laden.
@MainActor
private final class RadioLogoCache {
    static let shared = RadioLogoCache()
    private var images: [String: Image] = [:]
    private var missing: Set<String> = []

    func image(for name: String) -> Image? { images[name] }

    func load(_ name: String) async -> Image? {
        if let image = images[name] { return image }
        guard !missing.contains(name) else { return nil }
        for url in ChannelLogo.radioCandidateURLs(for: name) {
            guard let (data, response) = try? await URLSession.shared.data(from: url) else {
                if Task.isCancelled { return nil }
                continue
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = Self.decode(data) else { continue }
            images[name] = image
            return image
        }
        if !Task.isCancelled { missing.insert(name) }
        return nil
    }

    private static func decode(_ data: Data) -> Image? {
        #if os(tvOS)
        return UIImage(data: data).map(Image.init(uiImage:))
        #else
        return NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

/// Senderlogo oder, solange keines da ist, eine Kachel mit dem Sendernamen in der Farbe der
/// Senderfamilie. So bleibt nie eine Lücke, auch für Sender, zu denen es kein Logo gibt.
struct RadioLogoView: View {
    let name: String
    let width: CGFloat
    let height: CGFloat

    @State private var image: Image?

    var body: some View {
        Self.face(name: name, image: image, width: width, height: height)
            .task(id: name) {
                image = RadioLogoCache.shared.image(for: name)
                guard image == nil else { return }
                let loaded = await RadioLogoCache.shared.load(name)
                if !Task.isCancelled { image = loaded }
            }
    }

    /// Logo bzw. Namenskachel als Bild, sobald vorhanden mit dem geladenen Logo.
    static func dockImage(for name: String) -> CGImage? {
        let renderer = ImageRenderer(content: face(name: name, image: RadioLogoCache.shared.image(for: name),
                                                   width: 256, height: 160))
        renderer.scale = 2
        return renderer.cgImage
    }

    private static func face(name: String, image: Image?, width: CGFloat, height: CGFloat) -> some View {
        let corner = max(height * 0.14, 4)
        return ZStack {
            if let image {
                RoundedRectangle(cornerRadius: corner).fill(Color.white)
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: corner))
            } else {
                RoundedRectangle(cornerRadius: corner).fill(tileColor(for: name))
                Text(name)
                    .font(.system(size: height * 0.3, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .padding(height * 0.08)
            }
        }
        .frame(width: width, height: height)
    }

    /// Feste Farbe je Senderfamilie.
    private static func tileColor(for name: String) -> Color {
        let family = RadioStations.familyTitle(of: name)
        let hue = family.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31 &+ $1.value) % 360 }
        return Color(hue: Double(hue) / 360, saturation: 0.55, brightness: 0.45)
    }
}

// MARK: Anzeige während Radio läuft

/// Anzeige anstelle des Bildes. Sie wandert langsam über den Bildschirm, damit auf OLED-Fernsehern
/// nichts einbrennt, falls der Bildschirmschoner abgeschaltet ist.
struct RadioCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    let group: ChannelGroup

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let slot = Int(context.date.timeIntervalSince1970 / 30)
            card
                .offset(x: UI.s(220) * sin(Double(slot) * 1.3), y: UI.s(120) * cos(Double(slot) * 0.7))
                .animation(.easeInOut(duration: 12), value: slot)
        }
    }

    /// Während des Umschaltens gehört der gemeldete Titel noch zum vorigen Sender.
    private var reportedTitle: String? {
        guard group.variants.contains(where: { $0.id == player.channel?.id }),
              let title = player.nowPlaying, !title.isEmpty,
              !EPGProgram.isPlaceholderTitle(title) else { return nil }
        return title
    }

    private var card: some View {
        VStack(spacing: UI.s(20)) {
            RadioLogoView(name: group.displayName, width: UI.s(300), height: UI.s(170))
            Text(group.displayName)
                .font(UI.font(60, .heavy))
                .lineLimit(1)
            if model.radioPaused {
                Text("Angehalten")
                    .font(UI.font(32))
                    .foregroundStyle(UI.secondary)
            } else {
                RadioProgramInfo(store: player.epgStore, station: group, fallbackTitle: reportedTitle)
            }
            Text("\(UI.back): zurück zum Fernsehen · \(UI.select): Radioliste · \(UI.upDown): anderer Sender")
                .font(UI.font(22))
                .foregroundStyle(UI.secondary)
                .padding(.top, UI.s(16))
        }
        .foregroundStyle(UI.text)
        .padding(UI.s(48))
    }
}

/// Laufende und folgende Sendung aus den Programmdaten des Signals. Sender ohne echte Programmdaten
/// zeigen nur `fallbackTitle` bzw. nichts.
private struct RadioProgramInfo: View {
    let store: EPGStore
    let station: ChannelGroup
    var fallbackTitle: String? = nil

    private func real(_ program: EPGProgram?) -> EPGProgram? {
        guard let program, !EPGProgram.isPlaceholderTitle(program.title) else { return nil }
        return program
    }

    var body: some View {
        let current = real(store.currentProgram(forChannelNames: station.epgNames))
        let next = real(store.nextProgram(forChannelNames: station.epgNames))
        VStack(spacing: UI.s(8)) {
            if let current {
                Text(current.title)
                    .font(UI.font(34, .bold))
                    .foregroundStyle(UI.text)
                Text("\(UI.timeFormatter.string(from: current.startDate)) – \(UI.timeFormatter.string(from: current.endDate))")
                    .font(UI.font(24))
                    .foregroundStyle(UI.secondary)
                if let subtitle = current.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(UI.font(26))
                        .foregroundStyle(UI.secondary)
                }
            } else if let fallbackTitle {
                Text(fallbackTitle)
                    .font(UI.font(32))
                    .foregroundStyle(UI.secondary)
            }
            if let next {
                Text("Ab \(UI.timeFormatter.string(from: next.startDate)): \(next.title)")
                    .font(UI.font(24))
                    .foregroundStyle(UI.secondary)
                    .padding(.top, UI.s(8))
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
}

// MARK: Radioliste

/// Eigene Liste statt eines Abschnitts in der Senderliste: So bleibt die Senderliste bis auf eine
/// Zeile unverändert. Gezeichnet werden nur die Zeilen in der Nähe des sichtbaren Bereichs, damit
/// auch das schnelle Blättern durch viele Sender auf dem Apple TV flüssig bleibt.
struct RadioListOverlay: View {
    @ObservedObject var model: AppModel
    let player: PlayerController
    let selectedID: String
    @Environment(\.windowSize) private var windowSize

    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private static let rowHeight: CGFloat = UI.s(72)
    private static let headerHeight: CGFloat = UI.s(44)
    private static let spacing: CGFloat = UI.s(6)

    private var isCompact: Bool {
        #if os(macOS)
        return windowSize.width < 760
        #else
        return false
        #endif
    }

    /// Zeile der Liste mit fester Position.
    private struct Line: Identifiable {
        enum Content {
            case header(String)
            case item(RadioListItem)
        }
        let id: String
        let content: Content
        let y: CGFloat
        let height: CGFloat
    }

    private func makeLines() -> [Line] {
        var result: [Line] = []
        var y = UI.s(8)
        func add(_ id: String, _ content: Line.Content, height: CGFloat) {
            result.append(Line(id: id, content: content, y: y, height: height))
            y += height + Self.spacing
        }
        if model.currentRadio != nil {
            add(RadioListItem.backToTV.id, .item(.backToTV), height: Self.rowHeight)
        }
        for section in model.radioSections {
            add("header-\(section.id)", .header(section.title), height: Self.headerHeight)
            for station in section.stations {
                let item = RadioListItem.station(section: section.id, group: station)
                add(item.id, .item(item), height: Self.rowHeight)
            }
        }
        return result
    }

    private var selectedStation: ChannelGroup? {
        for item in model.radioListItems where item.id == selectedID {
            if case .station(_, let group) = item { return group }
        }
        return nil
    }

    var body: some View {
        let lines = makeLines()
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: UI.s(14)) {
                GeometryReader { listGeo in
                    let rowWidth = max(listGeo.size.width - UI.s(40), 0)
                    let margin = listGeo.size.height * 0.75
                    let top = -scrollOffset - margin
                    let bottom = -scrollOffset + listGeo.size.height + margin
                    ZStack(alignment: .topLeading) {
                        ForEach(lines.filter { $0.y + $0.height >= top && $0.y <= bottom }) { line in
                            lineView(line)
                                .frame(width: rowWidth, height: line.height)
                                .offset(x: UI.s(20), y: line.y)
                        }
                    }
                    .frame(width: listGeo.size.width, height: listGeo.size.height, alignment: .topLeading)
                    .offset(y: scrollOffset)
                    .frame(width: listGeo.size.width, height: listGeo.size.height, alignment: .topLeading)
                    .clipped()
                    .onAppear {
                        viewportHeight = listGeo.size.height
                        updateScroll(lines: lines, animated: false)
                    }
                    .onChange(of: listGeo.size.height) { _, newHeight in
                        viewportHeight = newHeight
                        updateScroll(lines: lines, animated: false)
                    }
                }
                .onChange(of: selectedID) { _, _ in
                    updateScroll(lines: makeLines(), animated: true)
                }

                Text("\(UI.select): abspielen · \(UI.playPause): Favorit · ←/→: Gruppe · \(UI.back): zurück")
                    .font(UI.font(20))
                    .foregroundStyle(UI.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, UI.s(20))
            }
            .padding(.vertical, isCompact ? 16 : UI.s(44))
            .padding(.horizontal, isCompact ? 12 : UI.s(20))
            .frame(width: isCompact ? windowSize.width : UI.s(760))
            .frame(maxHeight: .infinity)
            .background(Color(red: 0.055, green: 0.063, blue: 0.086).opacity(0.97))
            .overlay(alignment: .trailing) {
                if !isCompact {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
                }
            }
            .foregroundStyle(UI.text)

            if !isCompact {
                ZStack {
                    Color.black.opacity(0.7)
                        .contentShape(Rectangle())
                        .onTapGesture { model.overlay = .none }
                    if let station = selectedStation {
                        RadioStationPane(player: player, station: station, isCurrent: station == model.currentRadio)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        #if os(macOS)
        .onMacScrollWheel { _, dy in
            scrollOffset = max(minScrollOffset(lines), min(0, scrollOffset + dy))
        }
        #endif
    }

    private func minScrollOffset(_ lines: [Line]) -> CGFloat {
        min(0, viewportHeight - ((lines.last.map { $0.y + $0.height } ?? 0) + UI.s(8)))
    }

    private func updateScroll(lines: [Line], animated: Bool) {
        guard viewportHeight > 0, let line = lines.first(where: { $0.id == selectedID }) else { return }
        let ideal = viewportHeight / 2 - (line.y + line.height / 2)
        let target = max(minScrollOffset(lines), min(0, ideal))
        if animated {
            withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.90)) { scrollOffset = target }
        } else {
            scrollOffset = target
        }
    }

    @ViewBuilder private func lineView(_ line: Line) -> some View {
        switch line.content {
        case .header(let title):
            Text(title)
                .font(UI.font(18, .bold))
                .foregroundStyle(UI.secondary.opacity(0.85))
                .padding(.horizontal, UI.s(20))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        case .item(let item):
            itemRow(item)
        }
    }

    private func itemRow(_ item: RadioListItem) -> some View {
        let station: ChannelGroup?
        if case .station(_, let group) = item { station = group } else { station = nil }
        return Button {
            model.activateRadioListItem(item)
        } label: {
            RadioRow(title: station?.displayName ?? "Zurück zum Fernsehen",
                     isStation: station != nil,
                     isCurrent: station != nil && station == model.currentRadio,
                     isFavorite: station.map { model.settings.favoriteRadioKeys.contains($0.key) } ?? false,
                     selected: item.id == selectedID)
                .equatable()
        }
        .buttonStyle(ListRowButtonStyle())
        // Die Fernbedienung steuert die Liste über AppModel.handle; auf dem Apple TV dürfen die
        // Knöpfe den Fokus nicht übernehmen (sonst wirken Klick und Pfeile auf eine andere Zeile).
        .focusable(false)
    }
}

/// Rechte Seite der Radioliste. Eigene Ansicht: Nur sie beobachtet den Player, dessen laufende
/// Meldungen sonst die ganze Liste neu zeichnen würden.
private struct RadioStationPane: View {
    @ObservedObject var player: PlayerController
    let station: ChannelGroup
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: UI.s(20)) {
            RadioLogoView(name: station.displayName, width: UI.s(300), height: UI.s(170))
            Text(station.displayName)
                .font(UI.font(48, .heavy))
                .foregroundStyle(UI.text)
                .multilineTextAlignment(.center)
            if isCurrent {
                Badge(text: "LÄUFT")
            }
            RadioProgramInfo(store: player.epgStore, station: station)
        }
        .padding(UI.s(48))
    }
}

/// Zeile der Radioliste. `Equatable`, damit beim Blättern nur die Zeilen neu gezeichnet werden,
/// deren Auswahl sich ändert.
private struct RadioRow: View, Equatable {
    let title: String
    let isStation: Bool
    let isCurrent: Bool
    let isFavorite: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: UI.s(16)) {
            if isStation {
                RadioLogoView(name: title, width: UI.s(84), height: UI.s(54))
            } else {
                Image(systemName: "tv")
                    .font(UI.font(28, .semibold))
                    .foregroundStyle(selected ? Color.black : UI.accent)
                    .frame(width: UI.s(84))
            }
            Text(title)
                .font(UI.font(26, .semibold))
                .foregroundStyle(selected ? Color.black : UI.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(UI.font(20))
                    .foregroundStyle(selected ? Color.black : UI.accent)
            }
            if isCurrent {
                Badge(text: "LÄUFT", dark: selected)
            }
        }
        .padding(.horizontal, UI.s(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(selected ? UI.text : (isCurrent ? Color.white.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: UI.s(14)))
        .contentShape(Rectangle())
        .focusLift(selected)
    }
}
