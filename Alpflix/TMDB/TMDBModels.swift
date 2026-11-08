import Foundation

enum MediaType: String, Codable, Hashable {
    case movie
    case tv

    /// Stremio eklentilerindeki tür adı.
    var addonType: String { self == .movie ? "movie" : "series" }
}

/// Uygulamanın her yerinde kullanılan yapım kısa bilgisi (kart, kütüphane, gezinme).
struct MediaRef: Codable, Hashable, Identifiable {
    let tmdbId: Int
    let type: MediaType
    var title: String
    var posterPath: String?
    var backdropPath: String?
    var year: Int?

    var id: String { "\(type.rawValue):\(tmdbId)" }
}

struct TMDBPage<T: Decodable>: Decodable {
    let page: Int?
    let results: [T]
    let totalPages: Int?
}

struct TMDBItem: Decodable, Hashable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let overview: String?

    /// [fallback]: liste uç noktası türü bildirmiyorsa (movie/popular gibi).
    func ref(fallback: MediaType? = nil) -> MediaRef? {
        let type: MediaType
        switch mediaType {
        case "movie": type = .movie
        case "tv": type = .tv
        case nil: guard let f = fallback else { return nil }; type = f
        default: return nil
        }
        let label = (type == .movie ? (title ?? name) : (name ?? title)) ?? ""
        guard !label.isEmpty else { return nil }
        return MediaRef(tmdbId: id, type: type, title: label, posterPath: posterPath, backdropPath: backdropPath, year: yearOf(releaseDate ?? firstAirDate))
    }
}

func yearOf(_ date: String?) -> Int? {
    guard let date, date.count >= 4 else { return nil }
    return Int(date.prefix(4))
}

func dateOf(_ value: String?) -> Date? {
    guard let value, value.count >= 10 else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: String(value.prefix(10)))
}

struct TMDBGenre: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct TMDBGenreList: Decodable {
    let genres: [TMDBGenre]
}

struct TMDBCastMember: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}

struct TMDBCredits: Decodable {
    let cast: [TMDBCastMember]?
}

struct TMDBExternalIds: Decodable {
    let imdbId: String?
}

struct TMDBSeasonSummary: Decodable, Hashable, Identifiable {
    let seasonNumber: Int
    let episodeCount: Int?
    let name: String?
    let posterPath: String?
    let airDate: String?

    var id: Int { seasonNumber }
}

struct TMDBEpisode: Decodable, Hashable, Identifiable {
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let runtime: Int?

    var id: String { "\(seasonNumber)x\(episodeNumber)" }

    var hasAired: Bool {
        guard let date = dateOf(airDate) else { return false }
        return date <= Date()
    }
}

struct TMDBSeason: Decodable {
    let seasonNumber: Int?
    let episodes: [TMDBEpisode]
}

struct TMDBDetail: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let genres: [TMDBGenre]?
    let seasons: [TMDBSeasonSummary]?
    let credits: TMDBCredits?
    let externalIds: TMDBExternalIds?
    let imdbId: String?
    let lastEpisodeToAir: TMDBEpisode?
    let nextEpisodeToAir: TMDBEpisode?
    let recommendations: TMDBPage<TMDBItem>?
    let status: String?
    let videos: TMDBVideos?

    var displayTitle: String { title ?? name ?? "" }
    var imdb: String? { imdbId ?? externalIds?.imdbId }
    var year: Int? { yearOf(releaseDate ?? firstAirDate) }
    var minutes: Int? { runtime ?? episodeRunTime?.first }

    /// Normal sezonlar (özel bölümler, sezon 0, hariç).
    var regularSeasons: [TMDBSeasonSummary] { (seasons ?? []).filter { $0.seasonNumber > 0 } }

    func ref(_ type: MediaType) -> MediaRef {
        MediaRef(tmdbId: id, type: type, title: displayTitle, posterPath: posterPath, backdropPath: backdropPath, year: year)
    }
}

struct TMDBVideos: Decodable {
    let results: [TMDBVideo]
}

struct TMDBVideo: Decodable, Hashable {
    let key: String
    let site: String?
    let type: String?
    let iso6391: String?
    let official: Bool?
}

extension TMDBDetail {
    /// Fragman: YouTube, önce Türkçe sonra İngilizce, resmî olanlar önce.
    var trailerURL: URL? {
        let all = (videos?.results ?? []).filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
        let ranked = all.sorted { a, b in
            func score(_ v: TMDBVideo) -> Int {
                (v.type == "Trailer" ? 4 : 0) + (v.iso6391 == "tr" ? 2 : 0) + ((v.official ?? false) ? 1 : 0)
            }
            return score(a) > score(b)
        }
        return ranked.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
    }
}

struct TMDBProvider: Decodable, Hashable, Identifiable {
    let providerId: Int
    let providerName: String
    let logoPath: String?

    var id: Int { providerId }
}

struct TMDBRegionProviders: Decodable {
    let link: String?
    let flatrate: [TMDBProvider]?
    let free: [TMDBProvider]?
    let ads: [TMDBProvider]?
}

struct TMDBProvidersResponse: Decodable {
    let results: [String: TMDBRegionProviders]
}

enum TMDBImage {
    static func poster(_ path: String?, size: String = "w342") -> URL? { url(path, size) }
    static func backdrop(_ path: String?) -> URL? { url(path, "w1280") }
    static func still(_ path: String?) -> URL? { url(path, "w300") }
    static func profile(_ path: String?) -> URL? { url(path, "w185") }
    static func logo(_ path: String?) -> URL? { url(path, "w92") }

    private static func url(_ path: String?, _ size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}
