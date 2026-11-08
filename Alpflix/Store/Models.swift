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

struct AppData: Codable {
    var titles: [String: TrackedTitle] = [:]
    var events: [WatchEvent] = []
    var progress: [String: PlaybackProgress] = [:]
    var addons: [InstalledAddon] = []
    /// "İzlemeye devam et"ten kaldırılanlar: anahtar → kaldırma zamanı.
    var dismissedContinue: [String: Date] = [:]
}

struct EpisodeRef: Hashable, Comparable, Codable {
    let season: Int
    let episode: Int

    static func < (a: EpisodeRef, b: EpisodeRef) -> Bool {
        a.season != b.season ? a.season < b.season : a.episode < b.episode
    }
}
