import Foundation

/// Dizide sıradaki bölüm: izlenen en ileri bölümden sonraki ilk yayınlanmış ve izlenmemiş bölüm
/// (hiç izlenmediyse ilk bölüm). Sezon bölüm sayıları ve son yayınlanan bölüm TMDB'den.
enum NextEpisode {
    static func aired(seasons: [TMDBSeasonSummary], last: TMDBEpisode?) -> [EpisodeRef] {
        guard let last else { return [] }
        var result: [EpisodeRef] = []
        for season in seasons where season.seasonNumber >= 1 && season.seasonNumber <= last.seasonNumber {
            let count = season.seasonNumber == last.seasonNumber ? last.episodeNumber : (season.episodeCount ?? 0)
            guard count > 0 else { continue }
            for e in 1...count { result.append(EpisodeRef(season: season.seasonNumber, episode: e)) }
        }
        return result
    }

    static func target(aired: [EpisodeRef], watched: Set<EpisodeRef>) -> EpisodeRef? {
        guard let furthest = watched.filter({ aired.contains($0) }).max() else { return aired.first }
        return aired.first { $0 > furthest && !watched.contains($0) }
    }
}

/// "Rastgele bölüm" (sitcomlar için): yayınlanmış bölümlerden önce izlenmemişler, hepsi izlendiyse
/// tümünden biri; son açılan üst üste gelmez.
enum RandomEpisode {
    static func pick(aired: [EpisodeRef], watched: Set<EpisodeRef>, avoid: EpisodeRef? = nil) -> EpisodeRef? {
        guard !aired.isEmpty else { return nil }
        let unwatched = aired.filter { !watched.contains($0) }
        var pool = unwatched.isEmpty ? aired : unwatched
        if let avoid, pool.count > 1 { pool.removeAll { $0 == avoid } }
        return pool.randomElement()
    }
}
