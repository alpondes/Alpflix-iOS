import Foundation

/// Alpflix Android yedeği (alpflix-yedek-….json.gz): tek JSON, gzip'li. Yalnız iOS'ta kullanılan
/// alanlar okunur: yapımlar, izleme kayıtları, kaldığın yerler, eklentiler.
enum AndroidBackup {
    struct File: Decodable {
        let schemaVersion: Int
        let data: Payload
    }

    struct Payload: Decodable {
        let trackedTitles: [Title]?
        let watchEvents: [Event]?
        let playbackProgress: [Progress]?
        let addons: [Addon]?
    }

    struct Title: Decodable {
        let tmdbId: Int
        let mediaType: String
        let imdbId: String?
        let displayTitle: String
        let year: Int?
        let status: String?
        let addedAt: Int64
    }

    struct Event: Decodable {
        let tmdbId: Int
        let mediaType: String
        let season: Int?
        let episode: Int?
        let watchedAt: Int64
    }

    struct Progress: Decodable {
        let tmdbId: Int
        let mediaType: String
        let season: Int?
        let episode: Int?
        let positionMs: Int64
        let durationMs: Int64
        let updatedAt: Int64
    }

    struct Addon: Decodable {
        let manifestUrl: String
        let manifestJson: String
        let enabled: Bool
    }

    static func parse(_ raw: Data) throws -> AppData {
        let json = gunzip(raw) ?? raw
        let file = try JSONDecoder().decode(File.self, from: json)
        var result = AppData()
        var titleRefs: [String: TrackedTitle] = [:]
        for t in file.data.trackedTitles ?? [] {
            guard let type = MediaType(rawValue: t.mediaType) else { continue }
            let ref = MediaRef(tmdbId: t.tmdbId, type: type, title: t.displayTitle, posterPath: nil, backdropPath: nil, year: t.year)
            titleRefs[ref.id] = TrackedTitle(
                ref: ref,
                imdbId: t.imdbId,
                status: t.status.flatMap(TitleStatus.init(rawValue:)),
                addedAt: Date(timeIntervalSince1970: TimeInterval(t.addedAt) / 1000)
            )
        }
        result.titles = titleRefs
        result.events = (file.data.watchEvents ?? []).compactMap { (e: Event) -> WatchEvent? in
            guard let type = MediaType(rawValue: e.mediaType) else { return nil }
            return WatchEvent(tmdbId: e.tmdbId, type: type, season: e.season, episode: e.episode, watchedAt: Date(timeIntervalSince1970: TimeInterval(e.watchedAt) / 1000))
        }
        for p in file.data.playbackProgress ?? [] {
            guard let type = MediaType(rawValue: p.mediaType) else { continue }
            let key = "\(type.rawValue):\(p.tmdbId)"
            let ref = titleRefs[key]?.ref ?? MediaRef(tmdbId: p.tmdbId, type: type, title: "", posterPath: nil, backdropPath: nil, year: nil)
            let item = PlaybackProgress(
                ref: ref,
                imdbId: titleRefs[key]?.imdbId,
                season: p.season,
                episode: p.episode,
                positionMs: p.positionMs,
                durationMs: p.durationMs,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(p.updatedAt) / 1000)
            )
            result.progress[item.key] = item
        }
        result.addons = (file.data.addons ?? []).compactMap { (a: Addon) -> InstalledAddon? in
            guard let bytes = a.manifestJson.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(AddonManifest.self, from: bytes) else { return nil }
            return InstalledAddon(manifestUrl: a.manifestUrl, manifest: manifest, enabled: a.enabled)
        }
        return result
    }

    /// gzip başlığını atlayıp DEFLATE gövdesini açar (Apple'ın "zlib" algoritması ham DEFLATE'tir).
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= bytes.count else { return nil }
            let extra = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + extra
        }
        if flags & 0x08 != 0 {
            while index < bytes.count && bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 {
            while index < bytes.count && bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }
        guard index < bytes.count - 8 else { return nil }
        let body = Data(bytes[index..<(bytes.count - 8)])
        return try? (body as NSData).decompressed(using: .zlib) as Data
    }
}
