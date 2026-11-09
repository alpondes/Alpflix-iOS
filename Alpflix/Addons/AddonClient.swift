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

    /// Bir eklentinin altyazıları ve sonucu (menüde gösterilir: kaç altyazı ya da neden boş).
    /// Yalın istek boş dönerse Stremio gibi dosya adıyla (`filename=` ek parametresi) bir kez daha sorulur.
    static func subtitles(_ addon: InstalledAddon, type: String, id: String, filename: String?) async -> SubtitleResult {
        var result = await subtitleQuery(addon, path: "\(type)/\(id)")
        if result.items.isEmpty, result.problem == nil, let filename, !filename.isEmpty,
           let encoded = filename.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) {
            let retry = await subtitleQuery(addon, path: "\(type)/\(id)/filename=\(encoded)")
            if !retry.items.isEmpty { result = retry }
        }
        return result
    }

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func subtitleQuery(_ addon: InstalledAddon, path: String) async -> SubtitleResult {
        let name = addon.manifest.name
        guard let url = URL(string: "\(addon.baseUrl)/subtitles/\(path).json") else {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleUnreadable)
        }
        let data: Data
        do {
            data = try await HTTP.data(url, timeout: 30)
        } catch HTTPError.status(let code) {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleHTTP(code))
        } catch let error as URLError where error.code == .timedOut {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleTimeout)
        } catch {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleNetwork)
        }
        guard let response = try? HTTP.plainDecoder.decode(SubtitlesResponse.self, from: data) else {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleUnreadable)
        }
        return SubtitleResult(addon: name, items: response.subtitles ?? [], problem: nil)
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

    /// Altyazı sunan bütün etkin eklentilerden (paralel); her eklentinin sonucu ayrı.
    static func allSubtitles(_ addons: [InstalledAddon], type: String, id: String, filename: String? = nil) async -> [SubtitleResult] {
        let usable = addons.filter { $0.enabled && $0.manifest.supports("subtitles", type: type, id: id) }
        return await withTaskGroup(of: SubtitleResult.self) { group in
            for addon in usable { group.addTask { await subtitles(addon, type: type, id: id, filename: filename) } }
            var all: [SubtitleResult] = []
            for await result in group { all.append(result) }
            return all.sorted { $0.addon < $1.addon }
        }
    }
}

/// Bir eklentinin altyazı sorgusunun sonucu.
struct SubtitleResult: Hashable {
    let addon: String
    let items: [AddonSubtitle]
    /// Boşsa neden (HTTP hatası, zaman aşımı, okunamayan yanıt).
    let problem: String?

    var summary: String {
        if let problem { return L.subtitleProblem(addon, problem) }
        return L.subtitleCount(addon, items.count)
    }
}
