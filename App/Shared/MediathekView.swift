import SwiftUI
import AVKit
import FritzTVKit

// MARK: Daten

@MainActor
final class MediathekStore: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var movies: [MediathekMovie] = []
    @Published private(set) var currentType: String = "movie"
    /// Lokale Änderungen der Merkliste, bis die Liste neu geladen wird.
    @Published private var bookmarkOverrides: [Int: Bool] = [:]
    private(set) var client: Press2arrClient?

    func load(address: String, type: String = "movie") async {
        state = .loading
        currentType = type
        do {
            let client = try Press2arrClient(address: address)
            self.client = client
            movies = try await client.mediathekMovies(type: type)
            bookmarkOverrides = [:]
            state = .ready
            DebugLog.log("Mediathek (\(type)): \(movies.count) Titel, Kino \(movies.filter(\.ranInCinema).count), Presse \(movies.filter(\.reviewedInPress).count)")
        } catch Press2arrClient.ClientError.badAddress {
            state = .failed("Keine gültige press2arr-Adresse. Bitte in den Einstellungen unter „Mediathek“ eintragen.")
        } catch {
            DebugLog.log("Mediathek fehlgeschlagen: \(error)")
            state = .failed("press2arr ist nicht erreichbar (\(error.localizedDescription)). Läuft die NAS, und ist das Heimnetz oder das VPN verbunden?")
        }
    }

    func isBookmarked(_ movie: MediathekMovie) -> Bool {
        bookmarkOverrides[movie.tmdbId] ?? movie.isBookmarked
    }

    func setBookmark(_ movie: MediathekMovie, _ value: Bool) async {
        guard let client else { return }
        do {
            try await client.setBookmark(id: movie.tmdbId, value)
            bookmarkOverrides[movie.tmdbId] = value
        } catch {
            // Merkliste ist nicht kritisch: Fehler still übergehen, der Knopf bleibt unverändert.
        }
    }
}

// MARK: Übersicht

/// Mediathek-Seite: Spielfilme aus den Mediatheken, gefiltert nach Kino und Presse (Daten von press2arr).
/// Hier gilt die normale Fokus-Steuerung von tvOS bzw. die Maus auf dem Mac.
struct MediathekView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var store = MediathekStore()
    @Environment(\.dismiss) private var dismiss
    @State private var cinemaOnly = false
    @State private var pressOnly = false
    @State private var sort: MediathekSort = .rating
    @State private var surpriseMovie: MediathekMovie?
    @State private var isSeries = false

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: MediathekMovie.self) { movie in
                    MovieDetailView(movie: movie, store: store)
                }
                .sheet(item: $surpriseMovie) { movie in
                    NavigationStack {
                        MovieDetailView(movie: movie, store: store)
                    }
                }
                #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Schließen") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                #endif
        }
        .preferredColorScheme(.dark)
        .task {
            if store.movies.isEmpty { await store.load(address: settings.press2arrAddress) }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: UI.s(24)) {
                ProgressView()
                Text("Lade Mediathek …").font(UI.font(30))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: UI.s(28)) {
                Text("Mediathek nicht verfügbar").font(UI.font(44, .bold))
                Text(message).font(UI.font(28)).foregroundStyle(UI.secondary).multilineTextAlignment(.center)
                Button("Erneut versuchen") {
                    Task { await store.load(address: settings.press2arrAddress) }
                }
            }
            .padding(UI.s(80))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            overview
        }
    }

    private var overview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: UI.s(56)) {
                header
                if cinemaOnly || pressOnly {
                    grid(MediathekShelf.sorted(MediathekShelf.filtered(store.movies, cinema: cinemaOnly, press: pressOnly),
                                               by: sort))
                } else {
                    shelf("Neu in der Mediathek", MediathekShelf.sorted(store.movies, by: .newest))
                    shelf("Bestbewertet", MediathekShelf.sorted(store.movies, by: .rating))
                    shelf("Lief im Kino", MediathekShelf.sorted(
                        MediathekShelf.filtered(store.movies, cinema: true, press: false), by: .rating))
                    shelf("In der Presse besprochen", MediathekShelf.sorted(
                        MediathekShelf.filtered(store.movies, cinema: false, press: true), by: .rating))
                    shelf("Merkliste", store.movies.filter { store.isBookmarked($0) })
                }
            }
            .padding(.vertical, UI.s(48))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: UI.s(20)) {
            Text("Mediathek").font(UI.font(64, .heavy))
            Text("\(store.movies.count) \(isSeries ? "Serien" : "Spielfilme") bei ARD, ZDF, arte, 3sat und Co.")
                .font(UI.font(28))
                .foregroundStyle(UI.secondary)
            HStack(spacing: UI.s(24)) {
                chip(isSeries ? "Kategorie: Serien" : "Kategorie: Filme", on: true) {
                    isSeries.toggle()
                    Task {
                        await store.load(address: settings.press2arrAddress, type: isSeries ? "series" : "movie")
                    }
                }
                chip(cinemaOnly ? "✓ Lief im Kino" : "Lief im Kino", on: cinemaOnly) { cinemaOnly.toggle() }
                chip(pressOnly ? "✓ In der Presse besprochen" : "In der Presse besprochen", on: pressOnly) { pressOnly.toggle() }
                if cinemaOnly || pressOnly {
                    chip("Sortierung: \(sort.label)", on: false) {
                        let all = MediathekSort.allCases
                        sort = all[((all.firstIndex(of: sort) ?? 0) + 1) % all.count]
                    }
                }
                chip("🎲 Überrasch mich!", on: false) {
                    let candidates = cinemaOnly || pressOnly
                        ? MediathekShelf.filtered(store.movies, cinema: cinemaOnly, press: pressOnly)
                        : store.movies
                    surpriseMovie = candidates.randomElement()
                }
            }
        }
        .padding(.horizontal, UI.s(80))
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(UI.font(26, .semibold))
        }
        .buttonStyle(.bordered)
        .tint(on ? UI.accent : nil)
    }

    @ViewBuilder private func shelf(_ title: String, _ movies: [MediathekMovie]) -> some View {
        if !movies.isEmpty {
            VStack(alignment: .leading, spacing: UI.s(12)) {
                Text(title).font(UI.font(36, .bold)).padding(.horizontal, UI.s(80))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: UI.s(40)) {
                        ForEach(Array(movies.prefix(30))) { movie in
                            posterLink(movie)
                        }
                    }
                    .padding(.horizontal, UI.s(80))
                    .padding(.vertical, UI.s(30))
                }
            }
        }
    }

    @ViewBuilder private func grid(_ movies: [MediathekMovie]) -> some View {
        if movies.isEmpty {
            Text("Keine Filme mit diesen Filtern.")
                .font(UI.font(28))
                .foregroundStyle(UI.secondary)
                .padding(.horizontal, UI.s(80))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: UI.s(240)), spacing: UI.s(40))], spacing: UI.s(56)) {
                ForEach(movies) { movie in
                    posterLink(movie)
                }
            }
            .padding(.horizontal, UI.s(80))
        }
    }

    private func posterLink(_ movie: MediathekMovie) -> some View {
        NavigationLink(value: movie) {
            PosterCard(movie: movie, bookmarked: store.isBookmarked(movie))
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: Poster

struct PosterCard: View {
    let movie: MediathekMovie
    let bookmarked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: UI.s(10)) {
            AsyncImage(url: movie.posterURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Text(movie.title)
                            .font(UI.font(24, .semibold))
                            .multilineTextAlignment(.center)
                            .padding(UI.s(16))
                    }
                }
            }
            .frame(width: UI.s(240), height: UI.s(360))
            .clipShape(RoundedRectangle(cornerRadius: UI.s(14)))
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: UI.s(6)) {
                    if movie.ranInCinema { tag("Kino") }
                    if movie.reviewedInPress { tag("Presse") }
                    if bookmarked { tag("Gemerkt") }
                }
                .padding(UI.s(10))
            }
            Text(movie.title)
                .font(UI.font(24, .semibold))
                .lineLimit(1)
            Text(MovieText.cardLine(movie))
                .font(UI.font(20))
                .foregroundStyle(UI.secondary)
                .lineLimit(1)
        }
        .frame(width: UI.s(240))
        .padding(UI.s(6))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(UI.font(18, .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, UI.s(10))
            .padding(.vertical, UI.s(4))
            .background(UI.accent, in: Capsule())
    }
}

enum MovieText {
    static func rating(_ value: Double?, source: String? = nil) -> String? {
        guard let value, value > 0 else { return nil }
        let number = String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return source.map { "\($0) \(number)" } ?? "★ \(number)"
    }

    static func cardLine(_ movie: MediathekMovie) -> String {
        [movie.year.map(String.init), rating(movie.rating), movie.channels.first]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    static func verdict(_ value: String?) -> String? {
        switch value {
        case "positiv": return "empfohlen"
        case "gemischt": return "gemischt"
        case "negativ": return "verrissen"
        case "kinotipp": return "Kinotipp"
        default: return nil
        }
    }
}

// MARK: Detailseite

private struct PlayItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct MovieDetailView: View {
    let movie: MediathekMovie
    @ObservedObject var store: MediathekStore
    @State private var detail: MovieDetail?
    @State private var loadError: String?
    @State private var playing: PlayItem?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: UI.s(48)) {
                HStack(alignment: .top, spacing: UI.s(56)) {
                    AsyncImage(url: movie.posterURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.08)
                        }
                    }
                    .frame(width: UI.s(300), height: UI.s(450))
                    .clipShape(RoundedRectangle(cornerRadius: UI.s(16)))

                    VStack(alignment: .leading, spacing: UI.s(18)) {
                        Text(movie.title).font(UI.font(56, .heavy))
                        if let original = movie.originalTitle, original != movie.title {
                            Text(original).font(UI.font(28)).italic().foregroundStyle(UI.secondary)
                        }
                        Text(metaLine).font(UI.font(26)).foregroundStyle(UI.secondary)
                        if let tagline = detail?.details?.tagline ?? movie.tagline, !tagline.isEmpty {
                            Text("„\(tagline)“").font(UI.font(28)).italic()
                        }
                        Text(detail?.overview ?? movie.overview ?? "")
                            .font(UI.font(28))
                            .lineLimit(8)
                        let makers = detail?.details?.makers ?? movie.makers
                        if !makers.isEmpty {
                            Text("Regie: " + makers.joined(separator: ", ")).font(UI.font(24)).foregroundStyle(UI.secondary)
                        }
                        if let cast = detail?.details?.cast, !cast.isEmpty {
                            Text("Mit: " + cast.prefix(5).map(\.name).joined(separator: ", "))
                                .font(UI.font(24))
                                .foregroundStyle(UI.secondary)
                        }
                        actions
                    }
                }

                if let detail {
                    if !detail.reviews.isEmpty {
                        section("In der Presse") {
                            ForEach(Array(detail.reviews.enumerated()), id: \.offset) { _, review in
                                reviewRow(review)
                            }
                        }
                    }
                    if !detail.cinemaEntries.isEmpty {
                        section("Im Kino gelaufen") {
                            ForEach(Array(detail.cinemaEntries.enumerated()), id: \.offset) { _, entry in
                                infoRow(title: entry.source ?? "Kino", text: entry.summary ?? "")
                            }
                        }
                    }
                } else if let loadError {
                    Text(loadError).font(UI.font(24)).foregroundStyle(UI.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(UI.s(80))
        }
        .background {
            ZStack {
                Color.black
                AsyncImage(url: movie.backdropURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
                .opacity(0.35)
                LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
        .task { await loadDetail() }
        #if os(tvOS)
        .fullScreenCover(item: $playing) { item in
            MediathekPlayer(url: item.url)
        }
        #else
        .sheet(item: $playing) { item in
            MediathekPlayer(url: item.url)
                .frame(minWidth: 1000, minHeight: 600)
        }
        #endif
    }

    private var metaLine: String {
        let runtime = (detail?.details?.runtime ?? movie.runtime).map { "\($0) Min." }
        let genres = (detail?.details?.genres ?? movie.genres).prefix(3).joined(separator: ", ")
        return [movie.year.map(String.init), runtime, genres.isEmpty ? nil : genres,
                MovieText.rating(movie.rating, source: movie.ratingSource)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        let hits = detail?.playableHits ?? []
        HStack(spacing: UI.s(20)) {
            ForEach(Array(hits.prefix(3).enumerated()), id: \.offset) { index, hit in
                Button {
                    if let url = hit.streamURL { playing = PlayItem(url: url) }
                } label: {
                    Text(hitLabel(hit, first: index == 0)).font(UI.font(26, .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(index == 0 ? UI.accent : Color.white.opacity(0.2))
            }
            Button {
                Task { await store.setBookmark(movie, !store.isBookmarked(movie)) }
            } label: {
                Text(store.isBookmarked(movie) ? "✓ Gemerkt" : "Merken").font(UI.font(26, .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, UI.s(12))
        if detail != nil && hits.isEmpty {
            Text("Gerade kein abspielbarer Mediathek-Link.").font(UI.font(24)).foregroundStyle(UI.secondary)
        }
    }

    private func hitLabel(_ hit: MovieDetail.Hit, first: Bool) -> String {
        var parts = [first ? "▶ Abspielen" : "▶", hit.channel ?? "Mediathek"]
        if let quality = hit.quality { parts.append(quality) }
        if hit.isOriginalVersion { parts.append("OV") }
        if hit.hasBurnedSubtitles { parts.append("mit UT") }
        return parts.joined(separator: " · ")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: UI.s(20)) {
            Text(title).font(UI.font(36, .bold))
            content()
        }
    }

    private func reviewRow(_ review: MovieDetail.Mention) -> some View {
        VStack(alignment: .leading, spacing: UI.s(8)) {
            HStack(spacing: UI.s(16)) {
                Text(review.source ?? "Presse").font(UI.font(26, .bold))
                if let verdict = MovieText.verdict(review.verdict) {
                    Text(verdict)
                        .font(UI.font(20, .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, UI.s(12))
                        .padding(.vertical, UI.s(4))
                        .background(UI.accent, in: Capsule())
                }
            }
            if let title = review.title { Text(title).font(UI.font(26, .semibold)) }
            if let summary = review.summary { Text(summary).font(UI.font(24)).foregroundStyle(UI.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.s(24))
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: UI.s(16)))
        #if os(tvOS)
        .focusable()   // damit die Fernbedienung bis hierher scrollen kann
        #endif
    }

    private func infoRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: UI.s(6)) {
            Text(title).font(UI.font(26, .bold))
            if !text.isEmpty { Text(text).font(UI.font(24)).foregroundStyle(UI.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.s(24))
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: UI.s(16)))
        #if os(tvOS)
        .focusable()
        #endif
    }

    private func loadDetail() async {
        guard detail == nil, let client = store.client else { return }
        do {
            detail = try await client.movie(id: movie.tmdbId)
        } catch {
            loadError = "Details nicht geladen: \(error.localizedDescription)"
        }
    }
}

// MARK: Wiedergabe

/// Spielt einen Mediathek-Film direkt von den Servern der Sender (MP4) mit Apples Player.
struct MediathekPlayer: View {
    let url: URL
    @State private var player = AVPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding()
            }
            #endif
    }
}
