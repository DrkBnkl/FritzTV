import SwiftUI
import FritzTVKit

/// Zeigt Suchergebnisse aus MediathekViewWeb für „Sendung verpasst“.
struct MediathekSearchResultsView: View {
    let title: String
    let results: [MediathekSearchResult]
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: UI.s(16)) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: UI.s(4)) {
                        Text("In der Mediathek gefunden").font(UI.font(36, .heavy))
                        Text("Suchbegriff: „\(title)“").font(UI.font(22)).foregroundStyle(UI.secondary)
                    }
                    Spacer()
                    Button("Schließen") { dismiss() }
                        .font(UI.font(22, .semibold))
                        #if os(macOS)
                        .keyboardShortcut(.cancelAction)
                        .keyboardShortcut(.escape, modifiers: [])
                        #endif
                }
                .padding(.horizontal, UI.s(32))
                .padding(.top, UI.s(24))

                if results.isEmpty {
                    VStack(spacing: UI.s(16)) {
                        Spacer()
                        Text("Keine passenden Sendungen in der Mediathek gefunden")
                            .font(UI.font(28, .semibold))
                            .foregroundStyle(UI.secondary)
                        Text("Manche Sendungen (z. B. Nachrichten oder lizenzierte Filme) stehen nicht in der Mediathek.")
                            .font(UI.font(22))
                            .foregroundStyle(UI.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: UI.s(8)) {
                                ForEach(results.indices, id: \.self) { index in
                                    let item = results[index]
                                    let isSelected = index == selectedIndex
                                    resultRow(item, isSelected: isSelected) {
                                        selectedIndex = index
                                        selectCurrent()
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, UI.s(24))
                            .padding(.bottom, UI.s(20))
                        }
                        .onChange(of: selectedIndex) { _, newIndex in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onReceive(NotificationCenter.default.publisher(for: .searchResultMove)) { notification in
                if let delta = notification.object as? Int, !results.isEmpty {
                    selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchResultSelect)) { _ in
                selectCurrent()
            }
            #if os(macOS)
            .onKeyPress(.upArrow) {
                if selectedIndex > 0 { selectedIndex -= 1 }
                return .handled
            }
            .onKeyPress(.downArrow) {
                if selectedIndex < results.count - 1 { selectedIndex += 1 }
                return .handled
            }
            .onKeyPress(.return) {
                selectCurrent()
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            #elseif os(tvOS)
            .onExitCommand {
                dismiss()
            }
            #endif
        }
    }

    private func selectCurrent() {
        guard results.indices.contains(selectedIndex),
              let url = results[selectedIndex].bestPlaybackURL else { return }
        onSelect(url)
        dismiss()
    }

    private func resultRow(_ item: MediathekSearchResult, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: UI.s(16)) {
                VStack(alignment: .leading, spacing: UI.s(6)) {
                    HStack {
                        Text(item.channel)
                            .font(UI.font(20, .bold))
                            .foregroundStyle(isSelected ? Color.black : UI.accent)
                        if !item.topic.isEmpty {
                            Text("· \(item.topic)")
                                .font(UI.font(20))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.7) : UI.secondary)
                        }
                        Spacer()
                        Text("\(item.duration / 60) Min.")
                            .font(UI.font(18, .medium))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.7) : UI.secondary)
                    }
                    Text(item.title)
                        .font(UI.font(26, .semibold))
                        .foregroundStyle(isSelected ? Color.black : UI.text)
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(UI.font(20))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.8) : UI.secondary)
                            .lineLimit(2)
                    }
                }
                if isSelected {
                    Image(systemName: "play.fill")
                        .font(UI.font(24))
                        .foregroundStyle(Color.black)
                        .padding(.leading, UI.s(8))
                }
            }
            .padding(.horizontal, UI.s(20))
            .padding(.vertical, UI.s(14))
            .background(isSelected ? UI.text : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: UI.s(14)))
            .overlay(
                RoundedRectangle(cornerRadius: UI.s(14))
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
