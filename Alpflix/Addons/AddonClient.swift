import Foundation

enum AddonError: Error {
    case invalidManifest
}

/// Stremio eklenti protokolü: manifest, kaynaklar (stream) ve altyazılar.
enum AddonClient {
    static func fetchManifest(_ url: String) async throws -> AddonManifest {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("stremio://") { text = "https://" + text.dropFirst("stremio://".count) }
        if !text.hasSuffix("manifest.json") { text = text.hasSuffix("/") ? text + "manifest.json" : text + "/manifest.json" }
        guard let manifestUrl = URL(string: text) else { throw HTTPError.badURL }
        let data = try await HTTP.data(manifestUrl, timeout: 15)
        guard let manifest = try? HTTP.plainDecoder.decode(AddonManifest.self, from: data) else { throw AddonError.invalidManifest }
        return manifest
    }

    static func normalizedManifestUrl(_ url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("stremio://") { text = "https://" + text.dropFirst("stremio://".count) }
        if !text.hasSuffix("manifest.json") { text = text.hasSuffix("/") ? text + "manifest.json" : text + "/manifest.json" }
        return text
    }

    /// Stremio kimliği: film "tt123", bölüm "tt123:1:5".
    static func stremioId(imdb: String, season: Int?, episode: Int?) -> String {
        if let season, let episode { return "\(imdb):\(season):\(episode)" }
        return imdb
    }

    static func streams(_ addon: InstalledAddon, type: String, id: String) async -> [StreamCandidate] {
        guard let url = URL(string: "\(addon.baseUrl)/stream/\(type)/\(id).json") else { return [] }
        guard let data = try? await HTTP.data(url, timeout: 25),
              let response = try? HTTP.plainDecoder.decode(StreamsResponse.self, from: data) else { return [] }
        return (response.streams ?? []).map { StreamCandidate(addonName: addon.manifest.name, stream: $0, info: StreamInfo.parse($0)) }
    }

    static func subtitles(_ addon: InstalledAddon, type: String, id: String) async -> [AddonSubtitle] {
        guard let url = URL(string: "\(addon.baseUrl)/subtitles/\(type)/\(id).json") else { return [] }
        guard let data = try? await HTTP.data(url, timeout: 20),
              let response = try? HTTP.plainDecoder.decode(SubtitlesResponse.self, from: data) else { return [] }
        return response.subtitles ?? []
    }

    /// Bütün etkin ve uygun eklentilerden kaynaklar (paralel), sıralı.
    static func allStreams(_ addons: [InstalledAddon], type: String, id: String) async -> [StreamCandidate] {
        let usable = addons.filter { $0.enabled && $0.manifest.supports("stream", type: type, id: id) }
        let results = await withTaskGroup(of: [StreamCandidate].self) { group in
            for addon in usable { group.addTask { await streams(addon, type: type, id: id) } }
            var all: [StreamCandidate] = []
            for await items in group { all += items }
            return all
        }
        return StreamInfo.sort(results)
    }

    static func allSubtitles(_ addons: [InstalledAddon], type: String, id: String) async -> [AddonSubtitle] {
        let usable = addons.filter { $0.enabled && $0.manifest.supports("subtitles", type: type, id: id) }
        return await withTaskGroup(of: [AddonSubtitle].self) { group in
            for addon in usable { group.addTask { await subtitles(addon, type: type, id: id) } }
            var all: [AddonSubtitle] = []
            for await items in group { all += items }
            return all
        }
    }
}
