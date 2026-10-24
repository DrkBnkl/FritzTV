import SwiftUI
import FritzTVKit

/// Programmübersicht (EPG) über alle Sender mit aktuellem Programm,
/// Folgesendung und 20:15-Highlight.
struct EPGOverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var focusPrimeTime = false
    @State private var selectedChannelNumber: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                Divider().background(Color.white.opacity(0.15))
                channelList
            }
            .onAppear {
                model.triggerEPGScan()
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
    }

    private var headerBar: some View {
        HStack(spacing: UI.s(24)) {
            Text("Programmübersicht").font(UI.font(44, .heavy))
            Spacer()

            Button(action: { focusPrimeTime = false }) {
                Text("Jetzt")
                    .font(UI.font(26, .semibold))
                    .foregroundStyle(!focusPrimeTime ? Color.black : UI.text)
                    .padding(.horizontal, UI.s(24))
                    .padding(.vertical, UI.s(10))
                    .background(!focusPrimeTime ? UI.text : Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: { focusPrimeTime = true }) {
                Text("Heute 20:15")
                    .font(UI.font(26, .semibold))
                    .foregroundStyle(focusPrimeTime ? Color.black : UI.text)
                    .padding(.horizontal, UI.s(24))
                    .padding(.vertical, UI.s(10))
                    .background(focusPrimeTime ? UI.text : Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Button("Schließen") { dismiss() }
                .font(UI.font(26, .semibold))
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                #endif

            if model.epgScanner.isScanning {
                HStack(spacing: UI.s(8)) {
                    ProgressView()
                    Text("Lade EPG: \(model.epgScanner.currentScanningChannel ?? "") …")
                        .font(UI.font(20))
                        .foregroundStyle(UI.secondary)
                }
                .padding(.leading, UI.s(16))
            }
        }
        .padding(.horizontal, UI.s(48))
        .padding(.vertical, UI.s(24))
    }

    private var channelList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: UI.s(16)) {
                ForEach(model.lineup?.entries ?? []) { entry in
                    channelRow(entry)
                }
            }
            .padding(.horizontal, UI.s(48))
            .padding(.vertical, UI.s(24))
        }
    }

    private func channelRow(_ entry: LineupEntry) -> some View {
        let schedule = player.epgStore.schedule(forChannelKey: entry.group.key)
        let now = Date()
        let primeDate = primeTimeToday()

        let programToShow = focusPrimeTime
            ? (schedule?.program(at: primeDate) ?? schedule?.currentProgram(at: now))
            : schedule?.currentProgram(at: now)

        let next = schedule?.nextProgram(at: now)
        let hasHLS = PublicHLSChannels.hlsURL(for: entry.group.key) != nil

        return HStack(alignment: .top, spacing: UI.s(32)) {
            // Sender-Spalte
            Button(action: {
                model.tune(to: entry.number)
                dismiss()
            }) {
                HStack(spacing: UI.s(16)) {
                    Text("\(entry.number)")
                        .font(UI.font(32, .bold))
                        .foregroundStyle(UI.secondary)
                        .frame(width: UI.s(50), alignment: .leading)
                    ChannelLogoView(channelName: entry.group.displayName, height: UI.s(32), maxWidth: UI.s(72))
                    Text(entry.group.displayName)
                        .font(UI.font(30, .semibold))
                        .foregroundStyle(UI.text)
                        .lineLimit(1)
                }
                .frame(width: UI.s(320), alignment: .leading)
            }
            .buttonStyle(.plain)

            // Programm-Spalte
            VStack(alignment: .leading, spacing: UI.s(8)) {
                if let prog = programToShow {
                    HStack(spacing: UI.s(16)) {
                        Text("\(Self.formatTime(prog.startDate)) – \(Self.formatTime(prog.endDate))")
                            .font(UI.font(24, .semibold))
                            .foregroundStyle(UI.accent)
                        Text(prog.title)
                            .font(UI.font(30, .bold))
                            .foregroundStyle(UI.text)
                            .lineLimit(1)
                    }

                    if prog.isLive(at: now) {
                        GeometryReader { geo in
                            let p = prog.progress(at: now)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(UI.accent)
                                    .frame(width: max(geo.size.width * p, UI.s(6)))
                            }
                        }
                        .frame(height: UI.s(6))
                    }

                    if let sub = prog.subtitle ?? prog.description {
                        Text(sub)
                            .font(UI.font(22))
                            .foregroundStyle(UI.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Keine Programmdaten für diesen Sender empfangen")
                        .font(UI.font(24))
                        .foregroundStyle(UI.secondary)
                }

                // Danach
                if !focusPrimeTime, let nextProg = next {
                    Text("Danach ab \(Self.formatTime(nextProg.startDate)): \(nextProg.title)")
                        .font(UI.font(22))
                        .foregroundStyle(UI.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Schnell-Aktionen
            HStack(spacing: UI.s(16)) {
                if hasHLS, let prog = programToShow, prog.isLive(at: now) {
                    Button("Von Anfang an") {
                        if let hls = PublicHLSChannels.hlsURL(for: entry.group.key) {
                            model.startHLSReplay(url: hls, startDate: prog.startDate)
                            dismiss()
                        }
                    }
                    .font(UI.font(20, .semibold))
                }

                if let prog = programToShow {
                    Button("Mediathek") {
                        model.searchMediathek(title: prog.title, channel: entry.group.displayName)
                    }
                    .font(UI.font(20, .semibold))
                }
            }
        }
        .padding(UI.s(24))
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UI.s(20)))
    }

    private func primeTimeToday() -> Date {
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comp.hour = 20
        comp.minute = 15
        return Calendar.current.date(from: comp) ?? Date()
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
