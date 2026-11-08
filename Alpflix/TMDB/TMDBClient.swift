import Foundation

enum TMDBError: Error {
    case noToken
}

/// TMDB v3 uç noktaları, v4 okuma anahtarıyla (Bearer). Dil Türkçe, bölge Türkiye.
actor TMDBClient {
    static let shared = TMDBClient()

    private let base = "https://api.themoviedb.org/3/"
    private let language = "tr-TR"
    private let region = "TR"
    private var detailCache: [String: TMDBDetail] = [:]
    private var seasonCache: [String: TMDBSeason] = [:]

    /// Kullanıcının girdiği anahtar (Ayarlar), yoksa derlemedeki.
    private var token: String {
        let user = UserDefaults.standard.string(forKey: SettingsKeys.tmdbToken)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return user.isEmpty ? BuildSecrets.tmdbToken : user
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        let token = self.token
        guard !token.isEmpty else { throw TMDBError.noToken }
        var components = URLComponents(string: base + path)
        var items = [URLQueryItem(name: "language", value: language)]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        components?.queryItems = items
        guard let url = components?.url else { throw HTTPError.badURL }
        let data = try await HTTP.data(url, headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"])
        return try HTTP.snakeDecoder.decode(T.self, from: data)
    }

    // MARK: Listeler

    func trending(page: Int = 1) async throws -> [MediaRef] {
        let result: TMDBPage<TMDBItem> = try await get("trending/all/week", ["page": "\(page)"])
        return result.results.compactMap { $0.ref() }
    }

    /// [list]: popular, top_rated, now_playing (film), on_the_air (dizi).
    func list(_ type: MediaType, _ list: String, page: Int = 1) async throws -> TMDBPage<TMDBItem> {
        var query = ["page": "\(page)"]
        if type == .movie { query["region"] = region }
        return try await get("\(type.rawValue)/\(list)", query)
    }

    func discover(_ type: MediaType, genre: Int?, page: Int) async throws -> TMDBPage<TMDBItem> {
        var query = ["page": "\(page)", "sort_by": "popularity.desc", "include_adult": "false"]
        if let genre { query["with_genres"] = "\(genre)" }
        if type == .movie { query["vote_count.gte"] = "50" }
        return try await get("discover/\(type.rawValue)", query)
    }

    func genres(_ type: MediaType) async throws -> [TMDBGenre] {
        let result: TMDBGenreList = try await get("genre/\(type.rawValue)/list")
        return result.genres
    }

    func search(_ text: String) async throws -> [MediaRef] {
        let result: TMDBPage<TMDBItem> = try await get("search/multi", ["query": text, "include_adult": "false"])
        return result.results.compactMap { $0.ref() }
    }

    /// Kimliksiz kaynaklar (Netflix listesi) için adla eşleme: önce birebir ad, yoksa ilk sonuç.
    func match(_ type: MediaType, name: String) async throws -> MediaRef? {
        let result: TMDBPage<TMDBItem> = try await get("search/\(type.rawValue)", ["query": name, "include_adult": "false"])
        let target = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let refs = result.results.prefix(8)
        let exact = refs.first { item in
            [item.title, item.name].compactMap { $0 }.contains { $0.lowercased().filter { $0.isLetter || $0.isNumber } == target }
        }
        return (exact ?? refs.first)?.ref(fallback: type)
    }

    /// Bir platforma son gelen yapımlar (Türkiye, abonelik): çıkış tarihine göre, film ve dizi karışık.
    func providerRecent(_ providerId: Int) async throws -> [MediaRef] {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        async let movies: TMDBPage<TMDBItem> = get("discover/movie", [
            "with_watch_providers": "\(providerId)", "watch_region": region, "with_watch_monetization_types": "flatrate",
            "sort_by": "primary_release_date.desc", "primary_release_date.lte": today,
        ])
        async let series: TMDBPage<TMDBItem> = get("discover/tv", [
            "with_watch_providers": "\(providerId)", "watch_region": region, "with_watch_monetization_types": "flatrate",
            "sort_by": "first_air_date.desc", "first_air_date.lte": today,
        ])
        let m = try await movies.results.compactMap { $0.ref(fallback: .movie) }
        let t = try await series.results.compactMap { $0.ref(fallback: .tv) }
        var merged: [MediaRef] = []
        for i in 0..<max(m.count, t.count) {
            if i < m.count { merged.append(m[i]) }
            if i < t.count { merged.append(t[i]) }
        }
        return merged.filter { $0.posterPath != nil }
    }

    /// Türkiye'deki abonelik platformları (dizi listesi, TMDB önceliğiyle).
    func regionProviders() async throws -> [TMDBProvider] {
        struct Response: Decodable { let results: [TMDBProvider] }
        let result: Response = try await get("watch/providers/tv", ["watch_region": region])
        return result.results
    }

    // MARK: Yakında

    private func isoDay(_ date: Date) -> String { String(ISO8601DateFormatter().string(from: date).prefix(10)) }

    /// Önümüzdeki [days] gün: platformların yeni dizileri, yeni sezon/bölümleri ve dijitale gelen filmler.
    func upcoming(_ platforms: [TMDBProvider], days: Int = 60) async -> [UpcomingEntry] {
        let today = Date()
        let from = isoDay(today)
        let until = isoDay(today.addingTimeInterval(Double(days) * 86400))
        var entries: [UpcomingEntry] = []
        for platform in platforms {
            let networks = PlatformNetworks.ids(platform.providerName)
            if !networks.isEmpty, let page: TMDBPage<TMDBItem> = try? await get("discover/tv", [
                "with_networks": networks.map { String($0) }.joined(separator: "|"),
                "first_air_date.gte": from, "first_air_date.lte": until, "sort_by": "popularity.desc",
            ]) {
                for item in page.results {
                    if let ref = item.ref(fallback: .tv), let date = dateOf(item.firstAirDate) {
                        entries.append(UpcomingEntry(date: date, ref: ref, kind: .newSeries, platform: platform, season: nil, episode: nil))
                    }
                }
            }
            let running: TMDBPage<TMDBItem>? = try? await get("discover/tv", [
                "with_watch_providers": "\(platform.providerId)", "watch_region": region, "with_watch_monetization_types": "flatrate",
                "air_date.gte": from, "air_date.lte": until, "sort_by": "popularity.desc",
            ])
            for item in (running?.results ?? []).prefix(15) {
                guard let ref = item.ref(fallback: .tv), !entries.contains(where: { $0.ref.id == ref.id }),
                      let show = try? await self.detail(.tv, item.id), let next = show.nextEpisodeToAir,
                      let date = dateOf(next.airDate), date >= Calendar.current.startOfDay(for: today) else { continue }
                let kind: UpcomingKind = next.episodeNumber == 1 && next.seasonNumber > 1 ? .newSeason : .newEpisode
                entries.append(UpcomingEntry(date: date, ref: ref, kind: kind, platform: platform, season: next.seasonNumber, episode: next.episodeNumber))
            }
        }
        // Dijitale gelecek filmler; platform, dijital çıkış notundan.
        if let movies: TMDBPage<TMDBItem> = try? await get("discover/movie", [
            "with_release_type": "4", "release_date.gte": from, "release_date.lte": until, "sort_by": "popularity.desc",
        ]) {
            for item in movies.results.prefix(20) {
                guard let ref = item.ref(fallback: .movie) else { continue }
                guard let dates: TMDBReleaseDates = try? await get("movie/\(item.id)/release_dates") else { continue }
                var digital: [(String, Date, String?)] = []
                for country in dates.results {
                    for entry in country.releaseDates where entry.type == 4 {
                        if let date = dateOf(entry.releaseDate), date >= Calendar.current.startOfDay(for: today) {
                            digital.append((country.iso31661, date, entry.note))
                        }
                    }
                }
                guard !digital.isEmpty else { continue }
                let matched = platforms.first { p in digital.contains { PlatformNetworks.noteMatches($0.2, p.providerName) } }
                let date = digital.first(where: { $0.0 == region })?.1 ?? digital.map { $0.1 }.min() ?? today
                entries.append(UpcomingEntry(date: date, ref: ref, kind: .digitalMovie, platform: matched, season: nil, episode: nil))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    // MARK: Ayrıntı

    func detail(_ type: MediaType, _ id: Int, fresh: Bool = false) async throws -> TMDBDetail {
        let key = "\(type.rawValue):\(id)"
        if !fresh, let cached = detailCache[key] { return cached }
        let detail: TMDBDetail = try await get(
            "\(type.rawValue)/\(id)",
            ["append_to_response": "credits,external_ids,recommendations,videos", "include_video_language": "tr,en,null"]
        )
        detailCache[key] = detail
        return detail
    }

    /// Türkiye'de abonelikle / ücretsiz izlenebildiği platformlar (veri JustWatch'tan).
    func providers(_ type: MediaType, _ id: Int) async throws -> [TMDBProvider] {
        let result: TMDBProvidersResponse = try await get("\(type.rawValue)/\(id)/watch/providers")
        guard let tr = result.results[region] else { return [] }
        var seen = Set<Int>()
        return ((tr.flatrate ?? []) + (tr.free ?? []) + (tr.ads ?? [])).filter { seen.insert($0.providerId).inserted }
    }

    func season(_ tvId: Int, _ number: Int) async throws -> TMDBSeason {
        let key = "\(tvId):\(number)"
        if let cached = seasonCache[key] { return cached }
        let season: TMDBSeason = try await get("tv/\(tvId)/season/\(number)")
        seasonCache[key] = season
        return season
    }
}

struct TMDBReleaseDates: Decodable {
    struct Country: Decodable {
        let iso31661: String
        let releaseDates: [Entry]
    }

    struct Entry: Decodable {
        let type: Int
        let releaseDate: String?
        let note: String?
    }

    let results: [Country]
}

enum SettingsKeys {
    static let tmdbToken = "tmdb_token"
    static let subtitleLanguage = "subtitle_language"
    static let autoPlayNext = "auto_play_next"
}
