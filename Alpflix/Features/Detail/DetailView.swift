import SwiftUI

@MainActor
final class DetailModel: ObservableObject {
    @Published var detail: TMDBDetail?
    @Published var error: String?
    @Published var season: Int = 1
    @Published var episodes: [TMDBEpisode] = []
    @Published var loadingEpisodes = false
    @Published var providers: [TMDBProvider] = []

    func load(_ ref: MediaRef, store: LibraryStore) async {
        do {
            let d = try await TMDBClient.shared.detail(ref.type, ref.tmdbId)
            detail = d
            error = nil
            store.updateRef(d.ref(ref.type))
            providers = (try? await TMDBClient.shared.providers(ref.type, ref.tmdbId)) ?? []
            if ref.type == .tv {
                let aired = NextEpisode.aired(seasons: d.regularSeasons, last: d.lastEpisodeToAir)
                let next = NextEpisode.target(aired: aired, watched: store.watchedEpisodes(ref.tmdbId))
                season = next?.season ?? d.regularSeasons.first?.seasonNumber ?? 1
                await loadSeason(ref.tmdbId, season)
            }
        } catch {
            self.error = errorText(error)
        }
    }

    func loadSeason(_ tvId: Int, _ number: Int) async {
        season = number
        loadingEpisodes = true
        defer { loadingEpisodes = false }
        episodes = (try? await TMDBClient.shared.season(tvId, number).episodes) ?? []
    }

    func aired() -> [EpisodeRef] {
        guard let d = detail else { return [] }
        return NextEpisode.aired(seasons: d.regularSeasons, last: d.lastEpisodeToAir)
    }
}

struct DetailView: View {
    let ref: MediaRef
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.openURL) private var openURL
    @StateObject private var model = DetailModel()
    @ObservedObject private var downloads = DownloadStore.shared
    @State private var confirmSeason = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            if let d = model.detail {
                content(d)
            } else if let error = model.error {
                MessageView(text: error) { Task { await model.load(ref, store: store) } }
                    .padding(.top, 80)
            } else {
                ProgressView().tint(Theme.accent).padding(.top, 120).frame(maxWidth: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(model.detail?.displayTitle ?? ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.detail == nil { await model.load(ref, store: store) } }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(L.ok, role: .cancel) {}
        }
    }

    /// Sezonda yayınlanmış ve henüz indirilmemiş bölümler.
    private var seasonToDownload: [TMDBEpisode] {
        model.episodes.filter { e in
            e.hasAired && (downloads.item(ref, season: e.seasonNumber, episode: e.episodeNumber).map { $0.state == .failed } ?? true)
        }
    }

    private func downloadSeason(_ d: TMDBDetail, _ full: MediaRef) {
        guard let imdb = d.imdb, !imdb.isEmpty else { return }
        let episodes = model.episodes
        Task {
            let result = await downloads.enqueueSeason(ref: full, imdbId: imdb, episodes: episodes, addons: store.addons)
            notice = result.added + result.missing == 0 ? L.downloadSeasonNothing : L.downloadSeasonDone(result.added, result.missing)
        }
    }

    @ViewBuilder
    private func content(_ d: TMDBDetail) -> some View {
        let full = d.ref(ref.type)
        VStack(alignment: .leading, spacing: 20) {
            header(d)
            VStack(alignment: .leading, spacing: 12) {
                Text(d.displayTitle).font(Theme.title(28)).foregroundStyle(Theme.text)
                Text(meta(d)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                if let tagline = d.tagline, !tagline.isEmpty {
                    Text(tagline).font(Theme.body(15)).italic().foregroundStyle(Theme.textSecondary)
                }
                actions(d, full)
                if !model.providers.isEmpty { providerRow }
                if let overview = d.overview, !overview.isEmpty {
                    Text(overview).font(Theme.body(16)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.gutter)
            if ref.type == .tv { seasons(d, full) }
            cast(d)
            MediaRow(title: L.recommendations, items: (d.recommendations?.results ?? []).compactMap { $0.ref(fallback: ref.type) })
        }
        .padding(.bottom, 32)
    }

    private func header(_ d: TMDBDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: TMDBImage.backdrop(d.backdropPath)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Theme.surface
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipped()
            // Okunabilirlik için görselden zemine geçiş.
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
        }
        .frame(height: 230)
    }

    private func meta(_ d: TMDBDetail) -> String {
        var parts: [String] = []
        if let y = d.year { parts.append(String(y)) }
        if let g = d.genres?.prefix(3).map(\.name), !g.isEmpty { parts.append(g.joined(separator: ", ")) }
        if let m = d.minutes, m > 0 { parts.append(durationText(minutes: m)) }
        if ref.type == .tv { parts.append("\(d.regularSeasons.count) \(L.seasons.lowercased())") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func actions(_ d: TMDBDetail, _ full: MediaRef) -> some View {
        HStack(spacing: 10) {
            if let route = playRoute(d, full) {
                NavigationLink(value: route) {
                    Label(route.startMs > 0 ? L.resume : L.play, systemImage: "play.fill")
                        .font(Theme.body(16).weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.onAccent)
                }
            }
            Menu {
                ForEach(TitleStatus.allCases) { s in
                    Button {
                        store.setStatus(full, s, imdbId: d.imdb)
                    } label: {
                        if store.status(full) == s { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                    }
                }
                if store.status(full) != nil {
                    Button(L.removeStatus, role: .destructive) { store.setStatus(full, nil) }
                }
            } label: {
                Label(store.status(full)?.label ?? L.status, systemImage: store.status(full) == nil ? "plus" : "bookmark.fill")
                    .font(Theme.body(15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceHigh, in: Capsule())
                    .foregroundStyle(Theme.text)
            }
            if let trailer = d.trailerURL {
                Button { openURL(trailer) } label: {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.text)
                        .padding(8)
                }
                .accessibilityLabel(L.trailer)
            }
            if ref.type == .movie {
                let watched = store.isMovieWatched(ref.tmdbId)
                Button {
                    store.setWatched(full, watched: !watched, imdbId: d.imdb)
                } label: {
                    Image(systemName: watched ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(watched ? Theme.accent : Theme.text)
                        .padding(8)
                }
                .accessibilityLabel(watched ? L.markUnwatched : L.markWatched)
            }
        }
    }

    /// Nerede izlenir: Türkiye'deki platform logoları (veri JustWatch'tan, TMDB üzerinden).
    private var providerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.providers) { p in
                        AsyncImage(url: TMDBImage.logo(p.logoPath)) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Theme.surfaceHigh
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(p.providerName)
                    }
                }
            }
            Text(L.providersCredit).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
        }
    }

    /// Film: kaldığı yerden ya da baştan. Dizi: yarım bölüm varsa o, yoksa sıradaki bölüm.
    private func playRoute(_ d: TMDBDetail, _ full: MediaRef) -> SourcesRoute? {
        if ref.type == .movie {
            let p = store.progress(full, season: nil, episode: nil)
            let start = (p.map { $0.fraction < 0.95 } ?? false) ? (p?.positionMs ?? 0) : 0
            return SourcesRoute(ref: full, imdbId: d.imdb, season: nil, episode: nil, startMs: start)
        }
        if let resume = store.resumeItems().first(where: { $0.ref.tmdbId == ref.tmdbId && $0.ref.type == .tv }),
           let s = resume.season, let e = resume.episode {
            return SourcesRoute(ref: full, imdbId: d.imdb, season: s, episode: e, startMs: resume.positionMs)
        }
        let aired = model.aired()
        guard let next = NextEpisode.target(aired: aired, watched: store.watchedEpisodes(ref.tmdbId)) else { return nil }
        return SourcesRoute(ref: full, imdbId: d.imdb, season: next.season, episode: next.episode)
    }

    @ViewBuilder
    private func seasons(_ d: TMDBDetail, _ full: MediaRef) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L.seasons)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(d.regularSeasons) { s in
                        Button {
                            Task { await model.loadSeason(ref.tmdbId, s.seasonNumber) }
                        } label: {
                            Text(L.season(s.seasonNumber))
                                .font(Theme.body(14))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(model.season == s.seasonNumber ? Theme.accent : Theme.surfaceHigh, in: Capsule())
                                .foregroundStyle(model.season == s.seasonNumber ? Theme.onAccent : Theme.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            if let job = downloads.seasonJob {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text(L.downloadSeasonProgress(job.done, job.total)).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.gutter)
            } else if !model.loadingEpisodes, d.imdb?.isEmpty == false, !seasonToDownload.isEmpty {
                Button { confirmSeason = true } label: {
                    Label(L.downloadSeason, systemImage: "arrow.down.circle")
                        .font(Theme.body(14).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceHigh, in: Capsule())
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.gutter)
                .confirmationDialog(L.downloadSeasonConfirm(model.season, seasonToDownload.count), isPresented: $confirmSeason, titleVisibility: .visible) {
                    Button(L.downloadSeason) { downloadSeason(d, full) }
                    Button(L.cancel, role: .cancel) {}
                }
            }
            if model.loadingEpisodes {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding()
            }
            let watched = store.watchedEpisodes(ref.tmdbId)
            LazyVStack(spacing: 10) {
                ForEach(model.episodes) { e in
                    EpisodeRow(
                        episode: e,
                        watched: watched.contains(EpisodeRef(season: e.seasonNumber, episode: e.episodeNumber)),
                        downloaded: downloads.item(full, season: e.seasonNumber, episode: e.episodeNumber)?.state == .done,
                        route: SourcesRoute(ref: full, imdbId: d.imdb, season: e.seasonNumber, episode: e.episodeNumber, episodeTitle: e.name),
                        onToggle: { isWatched in
                            store.setWatched(full, season: e.seasonNumber, episode: e.episodeNumber, watched: !isWatched, imdbId: d.imdb)
                            store.refreshSeriesStatus(full, aired: model.aired())
                        }
                    )
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    @ViewBuilder
    private func cast(_ d: TMDBDetail) -> some View {
        let people = Array((d.credits?.cast ?? []).prefix(15))
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: L.cast)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(people) { person in
                            VStack(spacing: 6) {
                                AsyncImage(url: TMDBImage.profile(person.profilePath)) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Theme.surfaceHigh
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                Text(person.name).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.center)
                                if let role = person.character, !role.isEmpty {
                                    Text(role).font(Theme.body(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                }
                            }
                            .frame(width: 88)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }
}

/// Bölüm satırı: görsel, kod ve ad; dokununca kaynaklar, sağdaki işaretle izlendi.
struct EpisodeRow: View {
    let episode: TMDBEpisode
    let watched: Bool
    var downloaded = false
    let route: SourcesRoute
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: route) {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: TMDBImage.still(episode.stillPath)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Theme.surfaceHigh
                    }
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(watched ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(episodeCode(episode.seasonNumber, episode.episodeNumber)).font(Theme.mono(12)).foregroundStyle(Theme.accent)
                            if downloaded {
                                Image(systemName: "arrow.down.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                                    .accessibilityLabel(L.downloadDone)
                            }
                        }
                        Text(episode.name ?? "").font(Theme.body(15)).foregroundStyle(Theme.text).lineLimit(2)
                        if let runtime = episode.runtime, runtime > 0 {
                            Text(durationText(minutes: runtime)).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .disabled(!episode.hasAired)
            Button { onToggle(watched) } label: {
                Image(systemName: watched ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(watched ? Theme.accent : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(watched ? L.markUnwatched : L.markWatched)
        }
    }
}
