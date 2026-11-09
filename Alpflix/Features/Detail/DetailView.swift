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
    /// Tarih seçilerek izlendi işaretlenecek: film ya da bölüm(ler).
    @State private var dating: WatchDateTarget?

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
        .sheet(item: $dating) { target in
            WatchDateSheet(title: target.title) { date in
                apply(target, at: date)
            }
            .presentationDetents([.medium])
        }
    }

    private func apply(_ target: WatchDateTarget, at date: Date) {
        guard let d = model.detail else { return }
        let full = d.ref(ref.type)
        if target.episodes.isEmpty {
            store.setWatched(full, watched: true, imdbId: d.imdb, at: date)
        } else {
            store.markEpisodes(full, target.episodes, imdbId: d.imdb, at: date)
            store.refreshSeriesStatus(full, aired: model.aired())
        }
    }

    /// Bu bölüme kadar (dahil) yayınlanmış bütün bölümler.
    private func upTo(_ e: TMDBEpisode) -> [EpisodeRef] {
        let target = EpisodeRef(season: e.seasonNumber, episode: e.episodeNumber)
        return model.aired().filter { $0 <= target }
    }

    private func seasonEpisodes(_ season: Int) -> [EpisodeRef] {
        model.aired().filter { $0.season == season }
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
                let badges = SeriesBadges.of(d)
                if ref.type == .tv && !badges.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(Theme.mono(11).weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                if store.isHidden(full) {
                    Label(L.hiddenNotice, systemImage: "eye.slash").font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                }
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
                .contextMenu {
                    Button { dating = WatchDateTarget(title: d.displayTitle, episodes: []) } label: {
                        Label(L.markWatchedOnDate, systemImage: "calendar")
                    }
                }
            }
            AddToListMenu(ref: full)
            Menu {
                Button {
                    store.setHidden(full, !store.isHidden(full))
                } label: {
                    if store.isHidden(full) {
                        Label(L.unhide, systemImage: "eye")
                    } else {
                        Label(L.notInterested, systemImage: "eye.slash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .padding(8)
            }
            .accessibilityLabel(L.more)
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
            let seasonAired = seasonEpisodes(model.season)
            if !seasonAired.isEmpty {
                let watchedAll = seasonAired.allSatisfy { store.watchedEpisodes(ref.tmdbId).contains($0) }
                Menu {
                    if watchedAll {
                        Button(role: .destructive) { store.unmarkSeason(full, season: model.season) } label: {
                            Label(L.unmarkSeason, systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            store.markEpisodes(full, seasonAired, imdbId: d.imdb, at: Date())
                            store.refreshSeriesStatus(full, aired: model.aired())
                        } label: { Label(L.markSeason, systemImage: "checkmark.circle") }
                        Button {
                            dating = WatchDateTarget(title: L.season(model.season), episodes: seasonAired)
                        } label: { Label(L.markWatchedOnDate, systemImage: "calendar") }
                    }
                } label: {
                    Label(watchedAll ? L.seasonWatched : L.markSeason, systemImage: watchedAll ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(Theme.body(14).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceHigh, in: Capsule())
                        .foregroundStyle(watchedAll ? Theme.accent : Theme.text)
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
                    .contextMenu {
                        if e.hasAired {
                            Button {
                                store.markEpisodes(full, upTo(e), imdbId: d.imdb, at: Date())
                                store.refreshSeriesStatus(full, aired: model.aired())
                            } label: { Label(L.markUpTo, systemImage: "checkmark.circle.badge.questionmark") }
                            Button {
                                dating = WatchDateTarget(title: episodeCode(e.seasonNumber, e.episodeNumber),
                                                         episodes: [EpisodeRef(season: e.seasonNumber, episode: e.episodeNumber)])
                            } label: { Label(L.markWatchedOnDate, systemImage: "calendar") }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    @ViewBuilder
    private func cast(_ d: TMDBDetail) -> some View {
        // Yönetmenler önce (takip için kişi sayfası), sonra oyuncular.
        let directors = (d.credits?.crew ?? []).filter { $0.job == "Director" }.prefix(2).map {
            TMDBCastMember(id: $0.id, name: $0.name, character: L.departmentDirecting, profilePath: $0.profilePath)
        }
        let actors = (d.credits?.cast ?? []).filter { a in !directors.contains { $0.id == a.id } }
        let people = Array((directors + actors).prefix(16))
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: L.cast)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(people) { person in
                            NavigationLink(value: PersonRoute(id: person.id)) {
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
                            .buttonStyle(.plain)
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

struct WatchDateTarget: Identifiable {
    let title: String
    /// Boşsa film.
    let episodes: [EpisodeRef]
    var id: String { title + episodes.map { "\($0.season)x\($0.episode)" }.joined() }
}

/// İzleme tarihi seçimi (bugün ya da geçmiş bir gün).
struct WatchDateSheet: View {
    let title: String
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L.watchDate, selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) {
                        onSave(date)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Dizi durumu rozetleri: iptal edildi, final yaptı, yeni sezon (45 gün içinde başladı ya da yakında başlıyor).
enum SeriesBadges {
    static func of(_ d: TMDBDetail, now: Date = Date()) -> [String] {
        var badges: [String] = []
        switch d.status {
        case "Canceled": badges.append(L.badgeCanceled)
        case "Ended": badges.append(L.badgeEnded)
        default: break
        }
        if let next = d.nextEpisodeToAir, next.episodeNumber == 1, let date = dateOf(next.airDate) {
            badges.append(L.badgeSeasonSoon(next.seasonNumber, shortDate(date)))
        } else if let last = d.lastEpisodeToAir, let premiere = d.seasons?.first(where: { $0.seasonNumber == last.seasonNumber }),
                  last.seasonNumber > 1, let start = dateOf(premiere.airDate),
                  now.timeIntervalSince(start) < 45 * 86400, now >= start {
            badges.append(L.badgeNewSeason(last.seasonNumber))
        }
        if let next = d.nextEpisodeToAir, next.episodeNumber > 1, let date = dateOf(next.airDate) {
            badges.append(L.badgeNextEpisode(shortDate(date)))
        }
        return badges
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }
}
