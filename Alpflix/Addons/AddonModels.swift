import Foundation

/// Stremio eklenti manifesti. `resources` hem metin ("stream") hem nesne ({name, types, idPrefixes}) olabilir.
struct AddonManifest: Codable, Hashable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let resources: [AddonResource]
    let types: [String]
    let idPrefixes: [String]?
    let logo: String?

    /// Eklenti bu kaynak türü (stream, subtitles) için bu yapım türünü ve kimliği destekliyor mu?
    func supports(_ resource: String, type: String, id: String) -> Bool {
        guard let entry = resources.first(where: { $0.name == resource }) else { return false }
        let supportedTypes = entry.types ?? types
        guard supportedTypes.contains(type) else { return false }
        let prefixes = entry.idPrefixes ?? idPrefixes
        guard let prefixes, !prefixes.isEmpty else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }
}

struct AddonResource: Codable, Hashable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?

    private enum Keys: String, CodingKey { case name, types, idPrefixes }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            name = text
            types = nil
            idPrefixes = nil
            return
        }
        let container = try decoder.container(keyedBy: Keys.self)
        name = try container.decode(String.self, forKey: .name)
        types = try container.decodeIfPresent([String].self, forKey: .types)
        idPrefixes = try container.decodeIfPresent([String].self, forKey: .idPrefixes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(types, forKey: .types)
        try container.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
    }
}

struct InstalledAddon: Codable, Hashable, Identifiable {
    var manifestUrl: String
    var manifest: AddonManifest
    var enabled: Bool

    var id: String { manifestUrl }

    /// İstek tabanı: ".../manifest.json" öncesi.
    var baseUrl: String {
        var url = manifestUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("stremio://") { url = "https://" + url.dropFirst("stremio://".count) }
        if url.hasSuffix("/manifest.json") { url = String(url.dropLast("/manifest.json".count)) }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    /// Arayüzde gösterilen adres: yalnız alan adı (debrid anahtarı gizli).
    var maskedUrl: String {
        let host = URL(string: baseUrl)?.host ?? "?"
        return "\(host)/…/manifest.json"
    }
}

struct StreamsResponse: Decodable {
    let streams: [AddonStream]?
}

struct AddonStream: Decodable, Hashable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: StreamHints?
}

struct StreamHints: Decodable, Hashable {
    let bingeGroup: String?
    let filename: String?
}

struct SubtitlesResponse: Decodable {
    let subtitles: [AddonSubtitle]?
}

struct AddonSubtitle: Decodable, Hashable {
    let id: String?
    let url: String
    let lang: String?
}

/// Kaynak listesindeki tek satır: eklentiden gelen kaynak ve ondan okunanlar.
struct StreamCandidate: Identifiable, Hashable {
    let addonName: String
    let stream: AddonStream
    let info: StreamInfo

    var id: String { "\(addonName)|\(stream.url ?? stream.infoHash ?? "")|\(stream.fileIdx ?? -1)" }
    var playableURL: URL? { stream.url.flatMap { URL(string: $0) } }
}
