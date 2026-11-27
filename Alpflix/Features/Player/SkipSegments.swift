import Foundation

enum SkipKind: String, CaseIterable {
    case intro, recap, credits, preview

    var label: String {
        switch self {
        case .intro: return L.skipIntro
        case .recap: return L.skipRecap
        case .credits: return L.skipCredits
        case .preview: return L.skipPreview
        }
    }
}

/// Bölüm parçası; başlangıç yoksa 0, bitiş yoksa içeriğin sonu.
struct SkipSegment: Hashable {
    let kind: SkipKind
    let startMs: Int64?
    let endMs: Int64?

    func start() -> Int64 { startMs ?? 0 }
    func end(_ duration: Int64) -> Int64 { endMs ?? duration }
    func contains(_ position: Int64, _ duration: Int64) -> Bool { position >= start() && position < end(duration) }
}

/// TheIntroDB (topluluğun doldurduğu açık veritabanı): giriş, özet, jenerik ve önizleme zamanları;
/// eksik türler introdb.app'ten tamamlanır.
enum SkipSegments {
    static func url(tmdbId: Int, season: Int?, episode: Int?) -> URL? {
        var text = "https://api.theintrodb.org/v4/media?tmdb_id=\(tmdbId)"
        if let season, let episode, season > 0, episode > 0 { text += "&season=\(season)&episode=\(episode)" }
        return URL(string: text)
    }

    /// Cevap başka bölüme aitse (yanlış eşleşme) hiçbir parça kullanılmaz.
    static func parse(_ data: Data, season: Int?, episode: Int?) -> [SkipSegment] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        if let season, let episode {
            if let s = number(root["season"]), Int(s) != season { return [] }
            if let e = number(root["episode"]), Int(e) != episode { return [] }
        }
        var result: [SkipSegment] = []
        for kind in SkipKind.allCases {
            for item in (root[kind.rawValue] as? [[String: Any]]) ?? [] {
                let start = number(item["start_ms"])
                let end = number(item["end_ms"])
                if start == nil && end == nil { continue }
                if let start, let end, end <= start { continue }
                result.append(SkipSegment(kind: kind, startMs: start, endMs: end))
            }
        }
        return result
    }

    /// introdb.app (TheIntroDB'den ayrı, IMDb numarasıyla çalışan ikinci topluluk veritabanı; 2.2).
    static func introDbURL(imdbId: String, season: Int?, episode: Int?) -> URL? {
        guard imdbId.hasPrefix("tt") else { return nil }
        var text = "https://api.introdb.app/segments?imdb_id=\(imdbId)"
        if let season, let episode, season > 0, episode > 0 {
            text += "&season=\(season)&episode=\(episode)"
        } else {
            text += "&is_movie=true"
        }
        return URL(string: text)
    }

    /// introdb.app cevabı: her tür tek nesne ya da null (`outro` = jenerik). `post_credits` atlanmaz.
    static func parseIntroDb(_ data: Data) -> [SkipSegment] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let pairs: [(String, SkipKind)] = [("intro", .intro), ("recap", .recap), ("outro", .credits)]
        return pairs.compactMap { key, kind in
            guard let item = root[key] as? [String: Any], let end = number(item["end_ms"]), end > 0 else { return nil }
            let start = number(item["start_ms"])
            if let start, end <= start { return nil }
            return SkipSegment(kind: kind, startMs: start, endMs: end)
        }
    }

    /// Her tür için önce TheIntroDB, onda yoksa ikinci kaynak.
    static func merge(_ primary: [SkipSegment], _ secondary: [SkipSegment]) -> [SkipSegment] {
        primary + secondary.filter { s in !primary.contains { $0.kind == s.kind } }
    }

    /// Giriş, özet ya da jenerikten biri eksik mi.
    static func incomplete(_ segments: [SkipSegment]) -> Bool {
        [SkipKind.intro, .recap, .credits].contains { kind in !segments.contains { $0.kind == kind } }
    }

    static func active(_ segments: [SkipSegment], position: Int64, duration: Int64) -> SkipSegment? {
        guard duration > 0 else { return nil }
        return segments.first { $0.contains(position, duration) }
    }

    /// Jeneriğin başladığı an (bölümün ikinci yarısındaysa güvenilir): izlendi sayımı için.
    static func creditsStart(_ segments: [SkipSegment], duration: Int64) -> Int64? {
        guard duration > 0 else { return nil }
        let start = segments.filter { $0.kind == .credits && $0.startMs != nil }.map { $0.start() }.max()
        guard let start, start >= duration / 2 else { return nil }
        return start
    }

    private static func number(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String, let d = Double(s) { return Int64(d) }
        return nil
    }
}
