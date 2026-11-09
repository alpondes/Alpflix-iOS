import Foundation

/// Wyzie Subs (OpenSubtitles, SubDL, Podnapisi toplayıcısı): Ayarlar'da anahtar girildiyse eklentilere ek
/// altyazı kaynağı. Anahtar yoksa hiç istek atılmaz; anahtar yalnız cihazda (yedeğe girmez), log'lanmaz.
enum WyzieClient {
    private struct Item: Decodable {
        let url: String?
        let language: String?
        let display: String?
        let source: String?
        let isHearingImpaired: Bool?
    }

    static var key: String {
        UserDefaults.standard.string(forKey: SettingsKeys.wyzieKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func search(imdb: String, season: Int?, episode: Int?, preferred: String) async -> SubtitleResult? {
        let key = self.key
        guard !key.isEmpty, imdb.hasPrefix("tt") else { return nil }
        var components = URLComponents(string: "https://sub.wyzie.io/search")
        var query = [URLQueryItem(name: "id", value: imdb), URLQueryItem(name: "format", value: "srt")]
        if let season, let episode, season > 0, episode > 0 {
            query.append(URLQueryItem(name: "season", value: "\(season)"))
            query.append(URLQueryItem(name: "episode", value: "\(episode)"))
        }
        let languages = [preferred, "en"].filter { $0 != "none" && $0.count == 2 }
        var unique: [String] = []
        for l in languages where !unique.contains(l) { unique.append(l) }
        if !unique.isEmpty { query.append(URLQueryItem(name: "language", value: unique.joined(separator: ","))) }
        query.append(URLQueryItem(name: "key", value: key))
        components?.queryItems = query
        guard let url = components?.url else { return nil }
        let name = "Wyzie"
        let data: Data
        do {
            data = try await HTTP.data(url, timeout: 20)
        } catch HTTPError.status(let code) {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleHTTP(code))
        } catch {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleNetwork)
        }
        guard let items = try? HTTP.plainDecoder.decode([Item].self, from: data) else {
            return SubtitleResult(addon: name, items: [], problem: L.subtitleUnreadable)
        }
        var seen = Set<String>()
        let subs = items
            .sorted { ($0.isHearingImpaired ?? false ? 1 : 0) < ($1.isHearingImpaired ?? false ? 1 : 0) }
            .compactMap { item -> AddonSubtitle? in
                guard let url = item.url, !url.isEmpty, seen.insert(url).inserted else { return nil }
                return AddonSubtitle(id: [name, item.source].compactMap { $0 }.joined(separator: " · "), url: url, lang: item.language)
            }
        return SubtitleResult(addon: name, items: subs, problem: nil)
    }
}

/// Altyazı görünümü seçenekleri (VLC metin çizicisi). Boyutta küçük sayı büyük yazı demektir.
enum SubtitleStyle {
    struct Option {
        let label: String
        let value: Int
    }

    static let defaultSize = 16
    static let defaultColor = 0xEDE8E3

    static let sizes = [
        Option(label: L.sizeSmall, value: 20),
        Option(label: L.sizeNormal, value: 16),
        Option(label: L.sizeLarge, value: 12),
        Option(label: L.sizeHuge, value: 9),
    ]

    /// Saf beyaz yerine krem; sarı ve açık gri.
    static let colors = [
        Option(label: L.colorCream, value: 0xEDE8E3),
        Option(label: L.colorYellow, value: 0xF5D76E),
        Option(label: L.colorGray, value: 0xBDB3AD),
    ]
}
