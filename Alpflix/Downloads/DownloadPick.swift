import Foundation

/// İndirme kalitesi (Android `DownloadQuality` ile aynı): kendiliğinden seçimde (sezonu indir) hangi kaynak.
/// Netflix'in küçük ama net indirmeleri verimli sıkıştırmadan (HEVC/AV1) gelir; cihazda yeniden kodlama
/// yapılmaz, aynı yapımın küçük ve verimli sürümü seçilir.
enum DownloadQuality: String, CaseIterable, Identifiable {
    case small, balanced, best
    var id: String { rawValue }

    var maxResolution: Int {
        switch self {
        case .small: return 720
        case .balanced: return 1080
        case .best: return 2160
        }
    }

    /// GB sınırı: (bölüm, film); nil sınır yok.
    var caps: (episode: Double?, movie: Double?) {
        switch self {
        case .small: return (1.2, 2.5)
        case .balanced: return (2.5, 6)
        case .best: return (nil, nil)
        }
    }

    var label: String {
        switch self {
        case .small: return L.qualitySmall
        case .balanced: return L.qualityBalanced
        case .best: return L.qualityBest
        }
    }

    static var current: DownloadQuality {
        UserDefaults.standard.string(forKey: SettingsKeys.downloadQuality).flatMap(DownloadQuality.init(rawValue:)) ?? .balanced
    }
}

enum DownloadPick {
    private static func efficient(_ c: StreamCandidate) -> Bool { c.info.tags.contains("HEVC") || c.info.tags.contains("AV1") }

    /// İndirilebilir (http) kaynaklardan, kaliteye uyanlar içinde: hazır olan, aynı sürüm grubu, yüksek
    /// çözünürlük, verimli codec, küçük dosya. Hiçbiri uymazsa en küçük hazır kaynak.
    static func choose(_ candidates: [StreamCandidate], quality: DownloadQuality, isEpisode: Bool, group: String?) -> StreamCandidate? {
        let usable = candidates.filter { $0.playableURL?.scheme?.hasPrefix("http") == true && !$0.info.torrentOnly }
        guard !usable.isEmpty else { return nil }
        let cap = isEpisode ? quality.caps.episode : quality.caps.movie
        let fits = usable.filter { c in
            c.info.resolution <= quality.maxResolution && (cap == nil || c.info.sizeGB == nil || c.info.sizeGB! <= cap!)
        }
        func better(_ a: StreamCandidate, _ b: StreamCandidate) -> Bool {
            if a.info.cached != b.info.cached { return a.info.cached }
            let ga = group != nil && a.stream.behaviorHints?.bingeGroup == group
            let gb = group != nil && b.stream.behaviorHints?.bingeGroup == group
            if ga != gb { return ga }
            if a.info.resolution != b.info.resolution { return a.info.resolution > b.info.resolution }
            if efficient(a) != efficient(b) { return efficient(a) }
            return (a.info.sizeGB ?? .greatestFiniteMagnitude) < (b.info.sizeGB ?? .greatestFiniteMagnitude)
        }
        if let best = fits.sorted(by: better).first { return best }
        return usable.sorted { a, b in
            if a.info.cached != b.info.cached { return a.info.cached }
            return (a.info.sizeGB ?? .greatestFiniteMagnitude) < (b.info.sizeGB ?? .greatestFiniteMagnitude)
        }.first
    }
}
