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

/// TheIntroDB (topluluğun doldurduğu açık veritabanı): giriş, özet, jenerik ve önizleme zamanları.
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
