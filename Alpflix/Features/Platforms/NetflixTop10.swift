import Foundation

enum Top10Category: String, Codable { case films, tv }

/// Netflix'in haftalık ülke listesinden bir satır (Tudum verisi). [week]: haftanın son günü.
struct Top10Row: Codable, Hashable {
    let week: String
    let category: Top10Category
    let rank: Int
    let title: String
    let season: String?
    let weeks: Int

    var label: String { season ?? title }
}

struct Top10Entry: Identifiable, Hashable {
    let row: Top10Row
    let previousRank: Int?

    var id: String { row.label }
    var isNew: Bool { previousRank == nil }
    /// Pozitif: yükseldi, negatif: düştü.
    var movement: Int? { previousRank.map { $0 - row.rank } }
}

struct Top10Chart: Hashable {
    let week: String
    let category: Top10Category
    let entries: [Top10Entry]
}

/// Netflix Top 10 (Tudum "all-weeks-countries.tsv"): sekmeyle ayrılmış, ilk satır başlık. Dosya büyük;
/// akış hâlinde okunur, yalnız ülkenin satırları tutulur. Haftada bir yenilenir.
enum NetflixTop10 {
    static let dataURL = URL(string: "https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv")!

    static func parse<S: Sequence>(_ lines: S, country: String) -> [Top10Row] where S.Element == String {
        var iterator = lines.makeIterator()
        guard let headerLine = iterator.next() else { return [] }
        return parse(header: headerLine, rest: AnySequence { iterator }, country: country)
    }

    static func parse(header headerLine: String, rest: AnySequence<String>, country: String) -> [Top10Row] {
        let header = headerLine.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")).split(separator: "\t", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let iCountry = header.firstIndex(of: "country_iso2"),
              let iWeek = header.firstIndex(of: "week"),
              let iCategory = header.firstIndex(of: "category"),
              let iRank = header.firstIndex(of: "weekly_rank"),
              let iTitle = header.firstIndex(of: "show_title") else { return [] }
        let iSeason = header.firstIndex(of: "season_title")
        let iWeeks = header.firstIndex(of: "cumulative_weeks_in_top_10")
        var rows: [Top10Row] = []
        for line in rest {
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            func cell(_ i: Int?) -> String? { i.flatMap { $0 < cells.count ? cells[$0].trimmingCharacters(in: .whitespaces) : nil } }
            guard cell(iCountry)?.uppercased() == country.uppercased(),
                  let week = cell(iWeek), week.count == 10,
                  let categoryText = cell(iCategory)?.lowercased(),
                  let rank = cell(iRank).flatMap({ Int($0) }),
                  let title = cell(iTitle), !title.isEmpty else { continue }
            let category: Top10Category
            if categoryText.hasPrefix("film") { category = .films } else if categoryText.hasPrefix("tv") { category = .tv } else { continue }
            let season = cell(iSeason).flatMap { $0.isEmpty || $0.uppercased() == "N/A" ? nil : $0 }
            rows.append(Top10Row(week: week, category: category, rank: rank, title: title, season: season, weeks: cell(iWeeks).flatMap { Int($0) } ?? 1))
        }
        return rows
    }

    /// En son haftanın listesi, geçen haftaki sıralarla.
    static func chart(_ rows: [Top10Row], _ category: Top10Category) -> Top10Chart? {
        let inCategory = rows.filter { $0.category == category }
        let weeks = Array(Set(inCategory.map(\.week))).sorted(by: >)
        guard let latest = weeks.first else { return nil }
        let previous = weeks.count > 1 ? weeks[1] : nil
        var previousRanks: [String: Int] = [:]
        for r in inCategory where r.week == previous { previousRanks[r.label] = r.rank }
        let entries = inCategory.filter { $0.week == latest }.sorted { $0.rank < $1.rank }.map { Top10Entry(row: $0, previousRank: previousRanks[$0.label]) }
        return Top10Chart(week: latest, category: category, entries: entries)
    }
}

/// İndirme, önbellek (Caches/netflix_top10_tr.json) ve TMDB eşleme.
actor NetflixTop10Store {
    static let shared = NetflixTop10Store()

    private struct Stored: Codable {
        let fetchedAt: Date
        let rows: [Top10Row]
        var matches: [String: MediaRef]
    }

    private let file: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("netflix_top10_tr.json")
    private var stored: Stored?

    func load(force: Bool = false) async throws -> (films: Top10Chart?, tv: Top10Chart?, matches: [String: MediaRef]) {
        if stored == nil, let data = try? Data(contentsOf: file) { stored = try? JSONDecoder().decode(Stored.self, from: data) }
        let latest = stored?.rows.map(\.week).max()
        let stale = latest.flatMap { dateOf($0) }.map { Date().timeIntervalSince($0) > 9 * 24 * 3600 } ?? true
        if force || stored == nil || stale {
            let (bytes, response) = try await HTTP.session.bytes(from: NetflixTop10.dataURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw HTTPError.status(http.statusCode) }
            var lines: [String] = []
            var header: String?
            for try await line in bytes.lines {
                if header == nil { header = line; continue }
                // Yalnız Türkiye satırları bellekte tutulur.
                if line.contains("\tTR\t") { lines.append(line) }
            }
            let rows = NetflixTop10.parse(header: header ?? "", rest: AnySequence(lines), country: "TR")
            stored = Stored(fetchedAt: Date(), rows: rows, matches: stored?.matches ?? [:])
        }
        guard var current = stored else { return (nil, nil, [:]) }
        let films = NetflixTop10.chart(current.rows, .films)
        let tv = NetflixTop10.chart(current.rows, .tv)
        for entry in (films?.entries ?? []) + (tv?.entries ?? []) {
            let key = "\(entry.row.category.rawValue)|\(entry.row.title)"
            if current.matches[key] != nil { continue }
            let type: MediaType = entry.row.category == .films ? .movie : .tv
            if let hit = try? await TMDBClient.shared.match(type, name: entry.row.title) { current.matches[key] = hit }
        }
        stored = current
        if let data = try? JSONEncoder().encode(current) { try? data.write(to: file, options: .atomic) }
        return (films, tv, current.matches)
    }
}
