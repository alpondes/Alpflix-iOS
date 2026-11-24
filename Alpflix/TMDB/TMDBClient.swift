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

    /// Yapım ve sezon yanıtları diske de yazılır; bağlantı yokken (ya da hata verirse) oradan okunur:
    /// daha önce açılan sayfalar ve indirilen yapımlar internetsiz de görünür.
    private static let diskDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("tmdb-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = dir
        try? copy.setResourceValues(values)
        return dir
    }()

    private func cached<T: Codable>(_ key: String, _ load: () async throws -> T) async throws -> T {
        let file = Self.diskDir.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_") + ".json")
        do {
            let value = try await load()
            if let data = try? JSONEncoder().encode(value) { try? data.write(to: file, options: .atomic) }
            return value
        } catch {
            if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(T.self, from: data) { return value }
            throw error
        }
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:], language override: String? = nil) async throws -> T {
        let token = self.token
        guard !token.isEmpty else { throw TMDBError.noToken }
        var components = URLComponents(string: base + path)
        var items = [URLQueryItem(name: "language", value: override ?? language)]
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
    // MARK: Ad kuralı (Android ile aynı)

    /// en-US adları; kalıcı (yapım adı değişmez).
    private var englishNames: [String: String] = UserDefaults.standard.dictionary(forKey: "english_titles") as? [String: String] ?? [:]

    /// Türk yapımı özgün (Türkçe) adıyla, İngilizce yapım özgün adıyla, diğerleri İngilizce adıyla;
    /// İngilizce ad alınamazsa Latin harfli özgün ad, o da yoksa TMDB'nin Türkçe adı.
    func named(_ item: TMDBItem, fallback: MediaType) async -> MediaRef? {
        guard var ref = item.ref(fallback: fallback) else { return nil }
        let original = (ref.type == .movie ? item.originalTitle ?? item.originalName : item.originalName ?? item.originalTitle)?
            .trimmingCharacters(in: .whitespaces)
        switch item.originalLanguage ?? "" {
        case "":
            break
        case "tr":
            if let original, !original.isEmpty { ref.title = original }
        case "en":
            if let original, Self.isLatin(original) { ref.title = original }
        default:
            if let english = await englishTitle(ref) {
                ref.title = english
            } else if let original, Self.isLatin(original) {
                ref.title = original
            }
        }
        return ref
    }

    private func englishTitle(_ ref: MediaRef) async -> String? {
        if let known = englishNames[ref.id] { return known }
        struct Names: Decodable { let title: String?; let name: String? }
        let path = ref.type == .movie ? "movie/\(ref.tmdbId)" : "tv/\(ref.tmdbId)"
        guard let names: Names = try? await get(path, language: "en-US"),
              let english = (names.title ?? names.name)?.trimmingCharacters(in: .whitespaces),
              !english.isEmpty, Self.isLatin(english) else { return nil }
        englishNames[ref.id] = english
        UserDefaults.standard.set(englishNames, forKey: "english_titles")
        return english
    }

    /// Latin harfli mi (Korece, Japonca, Kiril vb. değil).
    static func isLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { $0.value < 0x0250 || (0x1E00...0x1EFF).contains($0.value) }
    }

    /// Platformdaki son çıkanlar (son 90 gün), çıkış tarihiyle; adlar uygulamanın kuralıyla.
    func providerRecentEntries(_ provider: TMDBProvider) async -> [PlatformAddition] {
        let today = Date()
        let from = isoDay(today.addingTimeInterval(-90 * 86400))
        let until = isoDay(today)
        async let movies: TMDBPage<TMDBItem>? = try? get("discover/movie", [
            "with_watch_providers": "\(provider.providerId)", "watch_region": region, "with_watch_monetization_types": "flatrate",
            "sort_by": "primary_release_date.desc", "primary_release_date.lte": until, "primary_release_date.gte": from,
        ])
        async let series: TMDBPage<TMDBItem>? = try? get("discover/tv", [
            "with_watch_providers": "\(provider.providerId)", "watch_region": region, "with_watch_monetization_types": "flatrate",
            "sort_by": "first_air_date.desc", "first_air_date.lte": until, "first_air_date.gte": from,
        ])
        var pairs: [(TMDBItem, MediaType)] = []
        for (page, type) in [(await movies, MediaType.movie), (await series, MediaType.tv)] {
            for item in page?.results ?? [] where item.posterPath != nil { pairs.append((item, type)) }
        }
        // Adlar (gerekirse İngilizce ad isteği) paralel.
        let named: [PlatformAddition?] = await pairs.concurrentMap { pair in
            let (item, type) = pair
            guard let date = dateOf(type == .movie ? item.releaseDate : item.firstAirDate),
                  let ref = await self.named(item, fallback: type) else { return nil }
            return PlatformAddition(ref: ref, date: date, platform: provider)
        }
        return named.compactMap { $0 }
    }

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
        // Platformlar paralel; her platformun kendi listesi, sonra birleştirilir.
        let perPlatform: [[UpcomingEntry]] = await platforms.concurrentMap(limit: 4) { platform in
            await self.upcomingFor(platform, from: from, until: until, today: today)
        }
        var entries: [UpcomingEntry] = []
        for list in perPlatform {
            for entry in list where !entries.contains(where: { $0.ref.id == entry.ref.id && $0.platform?.providerId == entry.platform?.providerId }) {
                entries.append(entry)
            }
        }
        entries += await digitalUpcoming(platforms, from: from, until: until, today: today)
        return entries.sorted { $0.date < $1.date }
    }

    private func upcomingFor(_ platform: TMDBProvider, from: String, until: String, today: Date) async -> [UpcomingEntry] {
        var entries: [UpcomingEntry] = []
        do {
            let networks = PlatformNetworks.ids(platform.providerName)
            if !networks.isEmpty, let page: TMDBPage<TMDBItem> = try? await get("discover/tv", [
                "with_networks": networks.map { String($0) }.joined(separator: "|"),
                "first_air_date.gte": from, "first_air_date.lte": until, "sort_by": "popularity.desc",
            ]) {
                let series: [UpcomingEntry?] = await page.results.concurrentMap { item in
                    guard let ref = await self.named(item, fallback: .tv), let date = dateOf(item.firstAirDate) else { return nil }
                    return UpcomingEntry(date: date, ref: ref, kind: .newSeries, platform: platform, season: nil, episode: nil)
                }
                entries += series.compactMap { $0 }
            }
            let running: TMDBPage<TMDBItem>? = try? await get("discover/tv", [
                "with_watch_providers": "\(platform.providerId)", "watch_region": region, "with_watch_monetization_types": "flatrate",
                "air_date.gte": from, "air_date.lte": until, "sort_by": "popularity.desc",
            ])
            let known = Set(entries.map(\.ref.id))
            let running15 = Array((running?.results ?? []).prefix(15))
            let found: [UpcomingEntry?] = await running15.concurrentMap { item in
                guard let ref = await self.named(item, fallback: .tv), !known.contains(ref.id),
                      let show = try? await self.detail(.tv, item.id), let next = show.nextEpisodeToAir,
                      let date = dateOf(next.airDate), date >= Calendar.current.startOfDay(for: today) else { return nil }
                let kind: UpcomingKind = next.episodeNumber == 1 && next.seasonNumber > 1 ? .newSeason : .newEpisode
                return UpcomingEntry(date: date, ref: ref, kind: kind, platform: platform, season: next.seasonNumber, episode: next.episodeNumber)
            }
            entries += found.compactMap { $0 }
        }
        return entries
    }

    /// Dijitale gelecek filmler; platform, dijital çıkış notundan.
    private func digitalUpcoming(_ platforms: [TMDBProvider], from: String, until: String, today: Date) async -> [UpcomingEntry] {
        var entries: [UpcomingEntry] = []
        if let movies: TMDBPage<TMDBItem> = try? await get("discover/movie", [
            "with_release_type": "4", "release_date.gte": from, "release_date.lte": until, "sort_by": "popularity.desc",
        ]) {
            let found: [UpcomingEntry?] = await Array(movies.results.prefix(20)).concurrentMap { item in
                guard let ref = await self.named(item, fallback: .movie) else { return nil }
                guard let dates: TMDBReleaseDates = try? await self.get("movie/\(item.id)/release_dates") else { return nil }
                var digital: [(String, Date, String?)] = []
                for country in dates.results {
                    for entry in country.releaseDates where entry.type == 4 {
                        if let date = dateOf(entry.releaseDate), date >= Calendar.current.startOfDay(for: today) {
                            digital.append((country.iso31661, date, entry.note))
                        }
                    }
                }
                guard !digital.isEmpty else { return nil }
                let matched = platforms.first { p in digital.contains { PlatformNetworks.noteMatches($0.2, p.providerName) } }
                let date = digital.first(where: { $0.0 == self.region })?.1 ?? digital.map { $0.1 }.min() ?? today
                return UpcomingEntry(date: date, ref: ref, kind: .digitalMovie, platform: matched, season: nil, episode: nil)
            }
            entries += found.compactMap { $0 }
        }
        return entries
    }

    // MARK: Akıllı liste, Türkiye ve mevsim satırları

    func smart(_ rule: SmartRule, page: Int) async throws -> TMDBPage<TMDBItem> {
        let dateKey = rule.type == .movie ? "primary_release_date" : "first_air_date"
        var query = ["page": "\(page)", "include_adult": "false", "vote_count.gte": rule.sort == .topVoted ? "200" : "20"]
        query["sort_by"] = rule.type == .tv && rule.sort == .newest ? "first_air_date.desc" : rule.sort.tmdb
        if !rule.genres.isEmpty { query["with_genres"] = rule.genres.map(String.init).joined(separator: ",") }
        if let from = rule.yearFrom { query["\(dateKey).gte"] = "\(from)-01-01" }
        if let to = rule.yearTo { query["\(dateKey).lte"] = "\(to)-12-31" }
        if rule.sort == .newest && rule.yearTo == nil { query["\(dateKey).lte"] = isoDay(Date()) }
        if let vote = rule.minVote { query["vote_average.gte"] = String(format: "%.1f", vote) }
        if let language = rule.language, !language.isEmpty { query["with_original_language"] = language }
        return try await get("discover/\(rule.type.rawValue)", query)
    }

    /// Türkiye'de abonelik platformlarında popüler (film ve dizi karışık).
    func turkeyPlatformsPopular() async throws -> [MediaRef] {
        let base = ["watch_region": region, "with_watch_monetization_types": "flatrate", "sort_by": "popularity.desc", "include_adult": "false"]
        async let movies: TMDBPage<TMDBItem> = get("discover/movie", base)
        async let series: TMDBPage<TMDBItem> = get("discover/tv", base)
        let m = try await movies.results.compactMap { $0.ref(fallback: .movie) }
        let t = try await series.results.compactMap { $0.ref(fallback: .tv) }
        var merged: [MediaRef] = []
        for i in 0..<max(m.count, t.count) {
            if i < t.count { merged.append(t[i]) }
            if i < m.count { merged.append(m[i]) }
        }
        return merged
    }

    /// Türk yapımları (özgün dil Türkçe), popülerliğe göre.
    func turkish(_ type: MediaType) async throws -> [MediaRef] {
        var query = ["with_original_language": "tr", "sort_by": "popularity.desc", "include_adult": "false"]
        let dateKey = type == .movie ? "primary_release_date" : "first_air_date"
        query["\(dateKey).gte"] = "\(Calendar.current.component(.year, from: Date()) - 3)-01-01"
        let page: TMDBPage<TMDBItem> = try await get("discover/\(type.rawValue)", query)
        return page.results.compactMap { $0.ref(fallback: type) }
    }

    /// Anahtar kelimeyle filmler (mevsim satırı); kelimenin kimliği TMDB'de aranır.
    func keywordMovies(_ keyword: String) async throws -> [MediaRef] {
        struct Keyword: Decodable { let id: Int; let name: String }
        let found: TMDBPage<Keyword> = try await get("search/keyword", ["query": keyword])
        guard let id = (found.results.first { $0.name.lowercased() == keyword } ?? found.results.first)?.id else { return [] }
        let page: TMDBPage<TMDBItem> = try await get("discover/movie", [
            "with_keywords": "\(id)", "sort_by": "popularity.desc", "vote_count.gte": "100", "include_adult": "false",
        ])
        return page.results.compactMap { $0.ref(fallback: .movie) }
    }

    func genreMovies(_ genre: Int) async throws -> [MediaRef] {
        let page: TMDBPage<TMDBItem> = try await get("discover/movie", [
            "with_genres": "\(genre)", "sort_by": "popularity.desc", "vote_count.gte": "300", "include_adult": "false",
        ])
        return page.results.compactMap { $0.ref(fallback: .movie) }
    }

    // MARK: Kişi

    func person(_ id: Int) async throws -> TMDBPerson {
        try await get("person/\(id)", ["append_to_response": "combined_credits"])
    }

    /// Bölümün oyuncuları: önce konuklar, sonra dizinin oyuncuları.
    func episodeCast(_ tvId: Int, season: Int, episode: Int) async throws -> [TMDBCastMember] {
        struct Episode: Decodable { let guestStars: [TMDBCastMember]?; let credits: TMDBCredits? }
        let e: Episode = try await get("tv/\(tvId)/season/\(season)/episode/\(episode)", ["append_to_response": "credits"])
        var seen = Set<Int>()
        return ((e.guestStars ?? []) + (e.credits?.cast ?? [])).filter { seen.insert($0.id).inserted }
    }

    /// IMDb kimliğinden TMDB yapımı (içe aktarma).
    func find(imdb: String) async throws -> MediaRef? {
        struct Found: Decodable { let movieResults: [TMDBItem]; let tvResults: [TMDBItem] }
        let found: Found = try await get("find/\(imdb)", ["external_source": "imdb_id"])
        return found.movieResults.first?.ref(fallback: .movie) ?? found.tvResults.first?.ref(fallback: .tv)
    }

    // MARK: Dijitale düşenler

    private var dropsCache: (at: Date, value: (recent: [DigitalDrop], upcoming: [DigitalDrop]))?

    /// ABD ve Türkiye'de son/önümüzdeki 30 günde dijital çıkışı olan popüler filmler; her birinin çıkış
    /// kayıtlarından sinema ve dijital tarihi. 6 saat bellekte.
    func digitalDrops() async -> (recent: [DigitalDrop], upcoming: [DigitalDrop]) {
        if let cache = dropsCache, Date().timeIntervalSince(cache.at) < 6 * 3600 { return cache.value }
        let today = Date()
        let from = isoDay(today.addingTimeInterval(-Double(DigitalDrops.windowDays) * 86400))
        let until = isoDay(today.addingTimeInterval(Double(DigitalDrops.windowDays) * 86400))
        var candidates: [TMDBItem] = []
        for region in ["US", "TR"] {
            for page in 1...2 {
                let result: TMDBPage<TMDBItem>? = try? await get("discover/movie", [
                    "region": region, "with_release_type": "4", "release_date.gte": from, "release_date.lte": until,
                    "sort_by": "popularity.desc", "include_adult": "false", "page": "\(page)",
                ])
                for item in result?.results ?? [] where !candidates.contains(where: { $0.id == item.id }) { candidates.append(item) }
            }
        }
        let drops = await withTaskGroup(of: DigitalDrop?.self) { group in
            for item in candidates.prefix(60) {
                guard let ref = item.ref(fallback: .movie) else { continue }
                group.addTask { await self.drop(ref) }
            }
            var all: [DigitalDrop] = []
            for await drop in group { if let drop { all.append(drop) } }
            return all
        }
        let value = DigitalDrops.split(drops, today: today)
        dropsCache = (Date(), value)
        return value
    }

    private func drop(_ ref: MediaRef) async -> DigitalDrop? {
        guard let dates: TMDBReleaseDates = try? await get("movie/\(ref.tmdbId)/release_dates") else { return nil }
        let entries = dates.results.flatMap { country in
            country.releaseDates.compactMap { r -> DigitalDrops.Entry? in
                guard let date = dateOf(r.releaseDate) else { return nil }
                return DigitalDrops.Entry(country: country.iso31661, type: r.type, date: date, note: r.note)
            }
        }
        return DigitalDrops.window(entries).map { DigitalDrop(ref: ref, window: $0) }
    }

    // MARK: Ayrıntı

    func detail(_ type: MediaType, _ id: Int, fresh: Bool = false) async throws -> TMDBDetail {
        let key = "\(type.rawValue):\(id)"
        if !fresh, let cached = detailCache[key] { return cached }
        let detail: TMDBDetail = try await cached("detail-\(key)") {
            try await get(
                "\(type.rawValue)/\(id)",
                ["append_to_response": "credits,external_ids,recommendations,videos", "include_video_language": "tr,en,null"]
            )
        }
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
        let season: TMDBSeason = try await cached("season-\(key)") { try await get("tv/\(tvId)/season/\(number)") }
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
    static let nightMode = "night_mode"
    static let stillWatchingEpisodes = "still_watching_episodes"
    static let episodeAlerts = "episode_alerts"
    static let wyzieKey = "local_wyzie_key"
    static let subtitleSize = "subtitle_size"
    static let subtitleColor = "subtitle_color"
    static let subtitleBold = "subtitle_bold"
    static let traktClientId = "local_trakt_client_id"
    static let traktUser = "trakt_user"
    static let downloadQuality = "download_quality"
}
