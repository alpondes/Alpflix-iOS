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

@MainActor
final class HomeModel: ObservableObject {
    @Published var trending: [MediaRef] = []
    @Published var movies: [MediaRef] = []
    @Published var series: [MediaRef] = []
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

    private var continueKey: String {
        "\(profiles.activeId)|\(store.data.events.count)|\(store.data.progress.count)|\(store.data.dismissedContinue.count)|\(store.data.progress.values.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !model.continueItems.isEmpty {
                    ContinueRow(items: model.continueItems) { store.dismissContinue($0.ref.id) }
                }
                MediaRow(title: L.watchlist, items: store.titles(with: .PLAN_TO_WATCH).map(\.ref))
                if let error = model.error {
                    MessageView(text: error) { Task { await model.load(force: true) } }
                }
                MediaRow(title: L.trending, items: model.trending)
                MediaRow(title: L.popularMovies, items: model.movies)
                MediaRow(title: L.popularSeries, items: model.series)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(L.tabHome)
        .toolbar {
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
        .task(id: continueKey) { await model.refreshContinue(store) }
    }
}

/// Yatay "İzlemeye devam et": dokununca kaynaklar (kaldığı yerden), basılı tutunca kaldırma.
struct ContinueRow: View {
    let items: [ContinueItem]
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
