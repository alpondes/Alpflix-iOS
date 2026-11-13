import Foundation

/// Kütüphane durumları; adlar Android ile aynı (yedek aktarımı).
enum TitleStatus: String, Codable, CaseIterable, Identifiable {
    case WATCHING, PLAN_TO_WATCH, ON_HOLD, DROPPED, COMPLETED

    var id: String { rawValue }

    var label: String {
        switch self {
        case .WATCHING: return L.statusWatching
        case .PLAN_TO_WATCH: return L.statusPlan
        case .ON_HOLD: return L.statusOnHold
        case .DROPPED: return L.statusDropped
        case .COMPLETED: return L.statusCompleted
        }
    }
}

struct TrackedTitle: Codable, Hashable {
    var ref: MediaRef
    var imdbId: String?
    var status: TitleStatus?
    var addedAt: Date
}

struct WatchEvent: Codable, Hashable {
    var tmdbId: Int
    var type: MediaType
    var season: Int?
    var episode: Int?
    var watchedAt: Date
}

/// Kaldığın yer; anahtar "movie:123" ya da "tv:123:s1e5".
struct PlaybackProgress: Codable, Hashable {
    var ref: MediaRef
    var imdbId: String?
    var season: Int?
    var episode: Int?
    var positionMs: Int64
    var durationMs: Int64
    var updatedAt: Date

    var key: String { PlaybackProgress.key(ref.tmdbId, ref.type, season, episode) }
    var fraction: Double { durationMs > 0 ? Double(positionMs) / Double(durationMs) : 0 }

    static func key(_ id: Int, _ type: MediaType, _ season: Int?, _ episode: Int?) -> String {
        if let season, let episode { return "\(type.rawValue):\(id):s\(season)e\(episode)" }
        return "\(type.rawValue):\(id)"
    }
}

/// Bütün kullanıcı verisi. Okuma esnektir: sonradan eklenen alanlar eski dosyada yoksa boş başlar
/// (yeni sürüm eski veriyi asla silmez).
struct AppData: Codable {
    var titles: [String: TrackedTitle] = [:]
    var events: [WatchEvent] = []
    var progress: [String: PlaybackProgress] = [:]
    var addons: [InstalledAddon] = []
    /// "İzlemeye devam et"ten kaldırılanlar: anahtar → kaldırma zamanı.
    var dismissedContinue: [String: Date] = [:]
    /// Yakında hatırlatıcıları.
    var reminders: [Reminder] = []
    /// Kendi listeleri ve akıllı listeler.
    var lists: [UserList] = []
    /// "İlgilenmiyorum" denenler: anahtar ("movie:123") → yapım.
    var hidden: [String: MediaRef] = [:]
    /// Takip edilen oyuncu/yönetmenler.
    var following: [FollowedPerson] = []
    /// Ana sayfa satırlarının sırası ve gizlenenler (boşsa varsayılan).
    var homeOrder: [String] = []
    var homeHidden: [String] = []
    /// İstatistik için yapım bilgisi (süre, türler); TMDB'den bir kez alınır.
    var facts: [String: TitleFacts] = [:]
    /// Wi-Fi eşitlemesi: durumların değişme zamanı (ms) ve kaldırılan izlemeler (180 gün).
    var syncStatusAt: [String: Int64] = [:]
    var syncDeletions: [SyncDeletion] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case titles, events, progress, addons, dismissedContinue, reminders, lists, hidden, following, homeOrder, homeHidden, facts
        case syncStatusAt, syncDeletions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titles = (try? c.decodeIfPresent([String: TrackedTitle].self, forKey: .titles)) ?? [:]
        events = (try? c.decodeIfPresent([WatchEvent].self, forKey: .events)) ?? []
        progress = (try? c.decodeIfPresent([String: PlaybackProgress].self, forKey: .progress)) ?? [:]
        addons = (try? c.decodeIfPresent([InstalledAddon].self, forKey: .addons)) ?? []
        dismissedContinue = (try? c.decodeIfPresent([String: Date].self, forKey: .dismissedContinue)) ?? [:]
        reminders = (try? c.decodeIfPresent([Reminder].self, forKey: .reminders)) ?? []
        lists = (try? c.decodeIfPresent([UserList].self, forKey: .lists)) ?? []
        hidden = (try? c.decodeIfPresent([String: MediaRef].self, forKey: .hidden)) ?? [:]
        following = (try? c.decodeIfPresent([FollowedPerson].self, forKey: .following)) ?? []
        homeOrder = (try? c.decodeIfPresent([String].self, forKey: .homeOrder)) ?? []
        homeHidden = (try? c.decodeIfPresent([String].self, forKey: .homeHidden)) ?? []
        facts = (try? c.decodeIfPresent([String: TitleFacts].self, forKey: .facts)) ?? [:]
        syncStatusAt = (try? c.decodeIfPresent([String: Int64].self, forKey: .syncStatusAt)) ?? [:]
        syncDeletions = (try? c.decodeIfPresent([SyncDeletion].self, forKey: .syncDeletions)) ?? []
    }
}

/// Kendi listesi; [rule] doluysa akıllı listedir (öğeleri TMDB'den kurala göre gelir).
struct UserList: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var items: [ListEntry] = []
    var rule: SmartRule?
    var createdAt: Date = Date()

    var isSmart: Bool { rule != nil }
}

struct ListEntry: Codable, Hashable {
    var ref: MediaRef
    var addedAt: Date
}

/// Akıllı liste kuralı (TMDB keşif sorgusu): tür, yıl aralığı, en düşük TMDB ortalaması, özgün dil.
/// TMDB ortalaması yalnız süzgeçtir; uygulamada kullanıcı puanı yok.
struct SmartRule: Codable, Hashable {
    var type: MediaType = .movie
    var genres: [Int] = []
    var yearFrom: Int?
    var yearTo: Int?
    var minVote: Double?
    var language: String?
    var sort: SmartSort = .popular
    /// İzlediklerim ve kütüphanemdekiler gösterilmesin.
    var hideKnown: Bool = true
}

enum SmartSort: String, Codable, CaseIterable, Identifiable {
    case popular, newest, topVoted
    var id: String { rawValue }

    var tmdb: String {
        switch self {
        case .popular: return "popularity.desc"
        case .newest: return "primary_release_date.desc"
        case .topVoted: return "vote_average.desc"
        }
    }

    var label: String {
        switch self {
        case .popular: return L.sortPopular
        case .newest: return L.sortNewest
        case .topVoted: return L.sortTopVoted
        }
    }
}

struct FollowedPerson: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    var profilePath: String?
    var department: String?
    var followedAt: Date
}

/// İstatistik için yapım bilgisi: dakika (dizide bölüm süresi) ve tür adları.
struct TitleFacts: Codable, Hashable {
    var minutes: Int
    var genres: [String]
}

/// "Hatırlat": Yakında'daki bir çıkış için o gün bildirim.
struct Reminder: Codable, Hashable, Identifiable {
    let ref: MediaRef
    let date: Date
    let kind: String
    let platform: String?
    let season: Int?
    let episode: Int?

    var id: String { [ref.id, season.map { "s\($0)" }, episode.map { "e\($0)" }].compactMap { $0 }.joined(separator: ":") }
}

struct EpisodeRef: Hashable, Comparable, Codable {
    let season: Int
    let episode: Int

    static func < (a: EpisodeRef, b: EpisodeRef) -> Bool {
        a.season != b.season ? a.season < b.season : a.episode < b.episode
    }
}

/// Ana sayfa satırları (sırası ve görünürlüğü Ayarlar'dan).
enum HomeRow: String, CaseIterable, Identifiable {
    case continueWatching, watchlist, seasonal, trending, turkeyPlatforms, turkishSeries, turkishMovies, popularMovies, popularSeries, following

    var id: String { rawValue }

    var label: String {
        switch self {
        case .continueWatching: return L.continueWatching
        case .watchlist: return L.watchlist
        case .seasonal: return L.homeSeasonal
        case .trending: return L.trending
        case .turkeyPlatforms: return L.homeTurkeyPlatforms
        case .turkishSeries: return L.homeTurkishSeries
        case .turkishMovies: return L.homeTurkishMovies
        case .popularMovies: return L.popularMovies
        case .popularSeries: return L.popularSeries
        case .following: return L.homeFollowing
        }
    }
}
