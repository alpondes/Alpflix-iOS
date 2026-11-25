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
        // Ek satırlar aynı anda yüklenir.
        let theme = SeasonalTheme.current()
        async let turkey = try? TMDBClient.shared.turkeyPlatformsPopular()
        async let trSeries = try? TMDBClient.shared.turkish(.tv)
        async let trMovies = try? TMDBClient.shared.turkish(.movie)
        async let season = Self.seasonalItems(theme)
        turkeyPlatforms = await turkey ?? turkeyPlatforms
        turkishSeries = await trSeries ?? turkishSeries
        turkishMovies = await trMovies ?? turkishMovies
        seasonalTitle = theme?.title
        seasonal = await season ?? []
    }

    private static func seasonalItems(_ theme: SeasonalTheme?) async -> [MediaRef]? {
        guard let theme else { return [] }
        if let keyword = theme.keyword { return try? await TMDBClient.shared.keywordMovies(keyword) }
        if let genre = theme.genre { return try? await TMDBClient.shared.genreMovies(genre) }
        return []
    }

    /// Takip edilen kişilerin son 90 günde çıkan ya da yakında çıkacak yapımları.
    func loadFollowing(_ people: [FollowedPerson]) async {
        guard !people.isEmpty else {
            followingNew = []
            return
        }
        let from = Date().addingTimeInterval(-90 * 86400)
        var found: [(MediaRef, Date)] = []
        let persons: [TMDBPerson?] = await Array(people.prefix(30)).concurrentMap { try? await TMDBClient.shared.person($0.id) }
        for p in persons.compactMap({ $0 }) {
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
        let recent = Array(store.recentSeries().prefix(20)).filter { !resuming.contains($0.0.tmdbId) }
        // Dizi bilgileri aynı anda; sonra sırayla işlenir.
        let details: [TMDBDetail?] = await recent.concurrentMap { try? await TMDBClient.shared.detail(.tv, $0.0.tmdbId) }
        for (index, (ref, at)) in recent.enumerated() {
            guard let detail = details[index] else { continue }
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
    @ObservedObject private var network = NetworkStatus.shared
    @ObservedObject private var downloads = DownloadStore.shared
    @State private var playingLocal: PlayRequest?

    private var continueKey: String {
        "\(profiles.activeId)|\(store.data.events.count)|\(store.data.progress.count)|\(store.data.dismissedContinue.count)|\(store.data.progress.values.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        // Öne çıkan görsel durum çubuğunun altına kadar uzanır; başlık çubuğu yerine kendi üst satırımız (2.1).
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    let hero = network.online ? store.visible(model.trending).first(where: { $0.backdropPath != nil }) : nil
                    if let hero {
                        HeroBanner(ref: hero, topInset: top) { HomeTopButtons(glass: true) }
                    } else {
                        homeHeader.padding(.top, top + 8)
                    }
                    // İnternetsiz: indirilenler en üstte, tek dokunuşla oynar.
                    if !network.online { offlineSection }
                    // Pano: her şey bir arada (2.0).
                    HomeDashboard()
                    if let error = model.error, network.online {
                        MessageView(text: error) { Task { await model.load(force: true) } }
                    }
                    ForEach(store.homeRows.filter { !store.isHomeRowHidden($0) }) { row in
                        rowView(row)
                    }
                }
                .frame(width: geo.size.width)
                .padding(.bottom, 16)
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(L.tabHome)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await model.load(force: true)
            await model.refreshContinue(store)
        }
        .task { await model.load() }
        .navigationDestination(item: $detailsRef) { DetailView(ref: $0) }
        .fullScreenCover(item: $playingLocal) { request in PlayerView(request: request).environmentObject(store) }
        .onChange(of: network.online) { _, online in
            // Bağlantı gelince boş kalan satırlar yeniden yüklenir.
            if online { Task { await model.load(force: true) } }
        }
        .task(id: store.data.following.count) { await model.loadFollowing(store.following) }
        .task { await EpisodeAlerts.refreshIfNeeded(store) }
        .task { await store.fillMissingPosters() }
        .task(id: continueKey) { await model.refreshContinue(store) }
    }
}

extension HomeView {
    /// Görsel yokken (yükleniyor, anahtar yok, çevrimdışı) üst satır: tarih, başlık, takvim ve profil.
    var homeHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.todayText).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                Text(L.tabHome).font(Theme.title(30)).foregroundStyle(Theme.text)
            }
            Spacer(minLength: 8)
            HomeTopButtons(glass: false)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private static var todayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE · d MMMM"
        return f.string(from: Date()).uppercaseTr
    }
    /// Çevrimdışı bölüm: uyarı, İndirilenler bağlantısı ve inmiş yapımlar (dokununca kaldığı yerden oynar).
    @ViewBuilder
    var offlineSection: some View {
        let ready = downloads.items.filter { $0.state == .done }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash").foregroundStyle(Theme.textSecondary)
                Text(L.offlineBanner).font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                NavigationLink(value: LibraryRoute.downloads) {
                    Text(L.downloads).font(Theme.body(14).weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.gutter)
            if ready.isEmpty {
                Text(L.offlineNoDownloads).font(Theme.body(13)).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.gutter)
            } else {
                SectionTitle(text: L.downloads)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(ready) { item in
                            Button {
                                let start = store.progress(item.ref, season: item.season, episode: item.episode)?.positionMs ?? 0
                                playingLocal = downloads.playRequest(item, startMs: start)
                            } label: {
                                PosterCard(ref: item.ref, subtitle: item.season.flatMap { s in item.episode.map { episodeCode(s, $0) } } ?? item.ref.year.map(String.init))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

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

/// Ana sayfanın üst köşesindeki takvim ve profil düğmeleri; görselin üstündeyken cam daireler.
struct HomeTopButtons: View {
    var glass: Bool
    @EnvironmentObject private var profiles: ProfileStore

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: LibraryRoute.calendar) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 42, height: 42)
                    .modifier(GlassCircle(enabled: glass))
            }
            .accessibilityLabel(L.calendar)
            NavigationLink { ProfilesView() } label: {
                ProfileAvatar(profile: profiles.active, size: 32)
                    .frame(width: 42, height: 42)
                    .modifier(GlassCircle(enabled: glass))
            }
            .accessibilityLabel(L.profiles)
        }
        .buttonStyle(.plain)
    }
}

private struct GlassCircle: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassCapsule()
        } else {
            content.background(Theme.tile, in: Circle()).overlay(GlassBorder(radius: 21))
        }
    }
}
