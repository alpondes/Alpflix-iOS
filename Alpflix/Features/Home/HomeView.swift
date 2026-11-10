import SwiftUI

/// "İzlemeye devam et" satırındaki kart: yarım kalan ya da sıradaki bölüm.
struct ContinueItem: Identifiable, Hashable {
    let ref: MediaRef
    let imdbId: String?
    let season: Int?
    let episode: Int?
    let progress: Double?
    let startMs: Int64
    let subtitle: String
    let at: Date

    var id: String { ref.id }
    var route: SourcesRoute { SourcesRoute(ref: ref, imdbId: imdbId, season: season, episode: episode, startMs: startMs) }
}

/// Mevsimlik satır: tarihine göre tek tema (yoksa satır görünmez).
struct SeasonalTheme {
    let title: String
    let keyword: String?
    let genre: Int?

    static func current(_ date: Date = Date()) -> SeasonalTheme? {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = c.month, let day = c.day else { return nil }
        switch (month, day) {
        case (12, _), (1, 1...6): return SeasonalTheme(title: L.seasonalNewYear, keyword: "christmas", genre: nil)
        case (10, 15...31), (11, 1...2): return SeasonalTheme(title: L.seasonalHalloween, keyword: "halloween", genre: nil)
        case (2, 1...14): return SeasonalTheme(title: L.seasonalValentine, keyword: nil, genre: 10749)
        case (6...8, _): return SeasonalTheme(title: L.seasonalSummer, keyword: "summer", genre: nil)
        default: return nil
        }
    }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var trending: [MediaRef] = []
    @Published var movies: [MediaRef] = []
    @Published var series: [MediaRef] = []
    @Published var turkeyPlatforms: [MediaRef] = []
    @Published var turkishSeries: [MediaRef] = []
    @Published var turkishMovies: [MediaRef] = []
    @Published var seasonal: [MediaRef] = []
    @Published var seasonalTitle: String?
    @Published var followingNew: [MediaRef] = []
    @Published var continueItems: [ContinueItem] = []
    @Published var error: String?
    private var loaded = false

    func load(force: Bool = false) async {
        guard force || !loaded else { return }
        do {
            async let t = TMDBClient.shared.trending()
            async let m = TMDBClient.shared.list(.movie, "popular")
            async let s = TMDBClient.shared.list(.tv, "popular")
            trending = try await t
            movies = try await m.results.compactMap { $0.ref(fallback: .movie) }
            series = try await s.results.compactMap { $0.ref(fallback: .tv) }
            error = nil
            loaded = true
        } catch {
            self.error = errorText(error)
        }
        turkeyPlatforms = (try? await TMDBClient.shared.turkeyPlatformsPopular()) ?? turkeyPlatforms
        turkishSeries = (try? await TMDBClient.shared.turkish(.tv)) ?? turkishSeries
        turkishMovies = (try? await TMDBClient.shared.turkish(.movie)) ?? turkishMovies
        if let theme = SeasonalTheme.current() {
            seasonalTitle = theme.title
            if let keyword = theme.keyword {
                seasonal = (try? await TMDBClient.shared.keywordMovies(keyword)) ?? []
            } else if let genre = theme.genre {
                seasonal = (try? await TMDBClient.shared.genreMovies(genre)) ?? []
            }
        } else {
            seasonalTitle = nil
            seasonal = []
        }
    }

    /// Takip edilen kişilerin son 90 günde çıkan ya da yakında çıkacak yapımları.
    func loadFollowing(_ people: [FollowedPerson]) async {
        guard !people.isEmpty else {
            followingNew = []
            return
        }
        let from = Date().addingTimeInterval(-90 * 86400)
        var found: [(MediaRef, Date)] = []
        for person in people.prefix(30) {
            guard let p = try? await TMDBClient.shared.person(person.id) else { continue }
            let credits = (p.combinedCredits?.cast ?? []) + (p.combinedCredits?.crew ?? []).filter { $0.job == "Director" }
            for credit in credits {
                guard let ref = credit.ref, let date = dateOf(credit.date), date >= from, ref.posterPath != nil,
                      !found.contains(where: { $0.0.id == ref.id }) else { continue }
                found.append((ref, date))
            }
        }
        followingNew = found.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    /// Yarım kalanlar ve son 30 günde izlenen dizilerin sıradaki bölümleri, son etkinliğe göre.
    func refreshContinue(_ store: LibraryStore) async {
        var items: [ContinueItem] = store.resumeItems().map { p in
            let left = max(1, Int((p.durationMs - p.positionMs) / 60_000))
            let code = (p.season != nil && p.episode != nil) ? episodeCode(p.season!, p.episode!) + " · " : ""
            return ContinueItem(ref: p.ref, imdbId: p.imdbId, season: p.season, episode: p.episode, progress: p.fraction,
                                startMs: p.positionMs, subtitle: code + L.minutesLeft(left), at: p.updatedAt)
        }
        let resuming = Set(items.filter { $0.ref.type == .tv }.map(\.ref.tmdbId))
        for (ref, at) in store.recentSeries().prefix(20) where !resuming.contains(ref.tmdbId) {
            guard let detail = try? await TMDBClient.shared.detail(.tv, ref.tmdbId) else { continue }
            let aired = NextEpisode.aired(seasons: detail.regularSeasons, last: detail.lastEpisodeToAir)
            store.refreshSeriesStatus(detail.ref(.tv), aired: aired)
            guard let next = NextEpisode.target(aired: aired, watched: store.watchedEpisodes(ref.tmdbId)) else { continue }
            let full = detail.ref(.tv)
            store.updateRef(full)
            items.append(ContinueItem(ref: full, imdbId: detail.imdb, season: next.season, episode: next.episode, progress: nil,
                                      startMs: 0, subtitle: L.nextUp(episodeCode(next.season, next.episode)), at: at))
        }
        // Yarım kalanların eksik kart bilgisi (yedekten gelenler) tamamlanır.
        for (index, item) in items.enumerated() where item.ref.posterPath == nil {
            if let detail = try? await TMDBClient.shared.detail(item.ref.type, item.ref.tmdbId) {
                let full = detail.ref(item.ref.type)
                store.updateRef(full)
                items[index] = ContinueItem(ref: full, imdbId: item.imdbId ?? detail.imdb, season: item.season, episode: item.episode,
                                            progress: item.progress, startMs: item.startMs, subtitle: item.subtitle, at: item.at)
            }
        }
        continueItems = items.sorted { $0.at > $1.at }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var profiles: ProfileStore
    @StateObject private var model = HomeModel()
    /// "İzlemeye devam et"te basılı tutup Detaylar: yapımın sayfası.
    @State private var detailsRef: MediaRef?

    private var continueKey: String {
        "\(profiles.activeId)|\(store.data.events.count)|\(store.data.progress.count)|\(store.data.dismissedContinue.count)|\(store.data.progress.values.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let error = model.error {
                    MessageView(text: error) { Task { await model.load(force: true) } }
                }
                ForEach(store.homeRows.filter { !store.isHomeRowHidden($0) }) { row in
                    rowView(row)
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(L.tabHome)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: LibraryRoute.calendar) { Image(systemName: "calendar") }
                    .accessibilityLabel(L.calendar)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ProfilesView() } label: { ProfileAvatar(profile: profiles.active, size: 30) }
                    .accessibilityLabel(L.profiles)
            }
        }
        .refreshable {
            await model.load(force: true)
            await model.refreshContinue(store)
        }
        .task { await model.load() }
        .navigationDestination(item: $detailsRef) { DetailView(ref: $0) }
        .task(id: store.data.following.count) { await model.loadFollowing(store.following) }
        .task { await EpisodeAlerts.refreshIfNeeded(store) }
        .task { await store.fillMissingPosters() }
        .task(id: continueKey) { await model.refreshContinue(store) }
    }
}

extension HomeView {
    @ViewBuilder
    func rowView(_ row: HomeRow) -> some View {
        switch row {
        case .continueWatching:
            let items = model.continueItems.filter { !store.isHidden($0.ref) }
            if !items.isEmpty {
                ContinueRow(items: items, onDetails: { detailsRef = $0.ref }) { store.dismissContinue($0.ref.id) }
            }
        case .watchlist: MediaRow(title: L.watchlist, items: store.titles(with: .PLAN_TO_WATCH).map(\.ref))
        case .seasonal: MediaRow(title: model.seasonalTitle ?? "", items: store.visible(model.seasonal))
        case .trending: MediaRow(title: L.trending, items: store.visible(model.trending))
        case .turkeyPlatforms: MediaRow(title: L.homeTurkeyPlatforms, items: store.visible(model.turkeyPlatforms))
        case .turkishSeries: MediaRow(title: L.homeTurkishSeries, items: store.visible(model.turkishSeries))
        case .turkishMovies: MediaRow(title: L.homeTurkishMovies, items: store.visible(model.turkishMovies))
        case .popularMovies: MediaRow(title: L.popularMovies, items: store.visible(model.movies))
        case .popularSeries: MediaRow(title: L.popularSeries, items: store.visible(model.series))
        case .following: MediaRow(title: L.homeFollowing, items: store.visible(model.followingNew))
        }
    }
}

/// Yatay "İzlemeye devam et": dokununca kaynaklar (kaldığı yerden), basılı tutunca kaldırma.
struct ContinueRow: View {
    let items: [ContinueItem]
    let onDetails: (ContinueItem) -> Void
    let onRemove: (ContinueItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L.continueWatching)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item.route) {
                            PosterCard(ref: item.ref, subtitle: item.subtitle, progress: item.progress)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { onDetails(item) } label: {
                                Label(item.ref.type == .tv ? L.seriesDetails : L.movieDetails, systemImage: "info.circle")
                            }
                            Button(role: .destructive) { onRemove(item) } label: {
                                Label(L.removeFromContinue, systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}
