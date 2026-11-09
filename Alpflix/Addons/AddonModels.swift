import Foundation

/// Stremio eklenti manifesti. `resources` hem metin ("stream") hem nesne ({name, types, idPrefixes}) olabilir.
struct AddonManifest: Codable, Hashable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let resources: [AddonResource]
    /// Bazı eklentiler türleri yalnız `resources` içinde verir.
    let types: [String]?
    let idPrefixes: [String]?
    let logo: String?

    private enum CodingKeys: String, CodingKey { case id, name, version, description, resources, types, idPrefixes, logo }
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    /// Hoşgörülü çözme: sürüm sayı olabilir, türler yalnız `resources` içinde olabilir, tanınmayan bir
    /// kaynak girdisi eklentinin tümden düşmesine yol açmaz.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? id
        if let text = try? c.decodeIfPresent(String.self, forKey: .version) {
            version = text
        } else if let number = try? c.decodeIfPresent(Double.self, forKey: .version) {
            version = String(number)
        } else {
            version = nil
        }
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        var parsed: [AddonResource] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .resources) {
            while !list.isAtEnd {
                if let item = try? list.decode(AddonResource.self) {
                    parsed.append(item)
                } else if (try? list.decode(Skip.self)) == nil {
                    break
                }
            }
        }
        resources = parsed
        types = try? c.decodeIfPresent([String].self, forKey: .types)
        idPrefixes = try? c.decodeIfPresent([String].self, forKey: .idPrefixes)
        logo = try? c.decodeIfPresent(String.self, forKey: .logo)
    }

    /// Eklenti bu kaynak türü (stream, subtitles) için bu yapım türünü ve kimliği destekliyor mu?
    func supports(_ resource: String, type: String, id: String) -> Bool {
        guard let entry = resources.first(where: { $0.name == resource }) else { return false }
        let supportedTypes = entry.types ?? types ?? []
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

/// Altyazı yanıtı: bozuk ya da adressiz tek bir öge bütün listeyi düşürmez.
struct SubtitlesResponse: Decodable {
    let subtitles: [AddonSubtitle]?

    private enum Keys: String, CodingKey { case subtitles }
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard var list = try? container.nestedUnkeyedContainer(forKey: .subtitles) else {
            subtitles = nil
            return
        }
        var items: [AddonSubtitle] = []
        while !list.isAtEnd {
            if let item = try? list.decode(AddonSubtitle.self) {
                items.append(item)
            } else if (try? list.decode(Skip.self)) == nil {
                break
            }
        }
        subtitles = items
    }
}

/// Eklenti altyazısı. OpenSubtitles gibi eklentilerde `id` sayı olarak gelebilir.
struct AddonSubtitle: Decodable, Hashable {
    let id: String?
    let url: String
    let lang: String?

    private enum Keys: String, CodingKey { case id, url, lang }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        url = try container.decode(String.self, forKey: .url)
        lang = try? container.decodeIfPresent(String.self, forKey: .lang)
        if let text = try? container.decodeIfPresent(String.self, forKey: .id) {
            id = text
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(number)
        } else {
            id = nil
        }
    }
}

/// Kaynak listesindeki tek satır: eklentiden gelen kaynak ve ondan okunanlar.
struct StreamCandidate: Identifiable, Hashable {
    let addonName: String
    let stream: AddonStream
    let info: StreamInfo

    var id: String { "\(addonName)|\(stream.url ?? stream.infoHash ?? "")|\(stream.fileIdx ?? -1)" }
    var playableURL: URL? { stream.url.flatMap { URL(string: $0) } }
}
