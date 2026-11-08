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

    // MARK: Ayrıntı

    func detail(_ type: MediaType, _ id: Int, fresh: Bool = false) async throws -> TMDBDetail {
        let key = "\(type.rawValue):\(id)"
        if !fresh, let cached = detailCache[key] { return cached }
        let append = type == .movie ? "credits,external_ids,recommendations" : "credits,external_ids,recommendations"
        let detail: TMDBDetail = try await get("\(type.rawValue)/\(id)", ["append_to_response": append])
        detailCache[key] = detail
        return detail
    }

    func season(_ tvId: Int, _ number: Int) async throws -> TMDBSeason {
        let key = "\(tvId):\(number)"
        if let cached = seasonCache[key] { return cached }
        let season: TMDBSeason = try await get("tv/\(tvId)/season/\(number)")
        seasonCache[key] = season
        return season
    }
}

enum SettingsKeys {
    static let tmdbToken = "tmdb_token"
    static let subtitleLanguage = "subtitle_language"
}
