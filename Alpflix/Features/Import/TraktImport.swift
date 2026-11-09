import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ImportKind { case watched, watchlist, listItem }

/// İçe aktarılacak tek kayıt. Trakt puanları hiç okunmaz.
struct ImportItem {
    let kind: ImportKind
    let title: String
    let year: Int?
    let type: MediaType
    let imdbId: String?
    let tmdbId: Int?
    var season: Int? = nil
    var episode: Int? = nil
    var watchedAt: Date? = nil
    var listName: String? = nil

    var matchKey: String {
        if let tmdbId { return "tmdb:\(type.rawValue):\(tmdbId)" }
        if let imdbId { return "imdb:\(imdbId)" }
        return "name:\(type.rawValue):\(title.lowercased()):\(year ?? 0)"
    }
}

/// Trakt JSON'u (dışa aktarım dosyaları ya da API yanıtları): geçmiş (watched_at), izlenenler
/// (watched-movies/shows), izleme listesi ve kişisel listeler (listed_at). Puan dosyaları atlanır.
enum TraktParser {
    static func parse(fileName: String, data: Data) -> (items: [ImportItem], ratings: Int) {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return ([], 0) }
        let array: [[String: Any]]
        if let list = root as? [[String: Any]] {
            array = list
        } else if let object = root as? [String: Any], let list = object["items"] as? [[String: Any]] {
            array = list
        } else {
            return ([], 0)
        }
        let lower = fileName.lowercased()
        if lower.contains("rating") { return ([], array.count) }
        let listName = lower.contains("watchlist") ? nil : listName(fileName)
        return (array.flatMap { item($0, listName: listName) }, 0)
    }

    private static func listName(_ fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        for prefix in ["lists-", "list-"] where base.lowercased().hasPrefix(prefix) {
            let name = String(base.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: " ")
            return name.isEmpty ? nil : name.prefix(1).uppercased() + name.dropFirst()
        }
        return nil
    }

    private static func item(_ obj: [String: Any], listName: String?) -> [ImportItem] {
        let type = obj["type"] as? String
        let movie = obj["movie"] as? [String: Any]
        let show = obj["show"] as? [String: Any]
        let episode = obj["episode"] as? [String: Any]
        if let watchedAt = obj["watched_at"] as? String {
            let at = date(watchedAt)
            if type == "episode", let show, let episode {
                var item = media(show, .tv, .watched)
                item.season = episode["season"] as? Int
                item.episode = episode["number"] as? Int
                item.watchedAt = at
                return [item]
            }
            if let movie {
                var item = media(movie, .movie, .watched)
                item.watchedAt = at
                return [item]
            }
            return []
        }
        if let last = obj["last_watched_at"] as? String {
            if let movie {
                var item = media(movie, .movie, .watched)
                item.watchedAt = date(last)
                return [item]
            }
            if let show {
                let seasons = obj["seasons"] as? [[String: Any]] ?? []
                return seasons.flatMap { season -> [ImportItem] in
                    (season["episodes"] as? [[String: Any]] ?? []).map { ep in
                        var item = media(show, .tv, .watched)
                        item.season = season["number"] as? Int
                        item.episode = ep["number"] as? Int
                        item.watchedAt = date(ep["last_watched_at"] as? String ?? last)
                        return item
                    }
                }
            }
        }
        if obj["listed_at"] != nil {
            let kind: ImportKind = listName == nil ? .watchlist : .listItem
            if let movie {
                var item = media(movie, .movie, kind)
                item.listName = listName
                return [item]
            }
            if let show {
                var item = media(show, .tv, kind)
                item.listName = listName
                return [item]
            }
        }
        return []
    }

    private static func media(_ obj: [String: Any], _ type: MediaType, _ kind: ImportKind) -> ImportItem {
        let ids = obj["ids"] as? [String: Any]
        let imdb = (ids?["imdb"] as? String).flatMap { $0.hasPrefix("tt") ? $0 : nil }
        return ImportItem(kind: kind, title: obj["title"] as? String ?? "", year: obj["year"] as? Int, type: type,
                          imdbId: imdb, tmdbId: ids?["tmdb"] as? Int)
    }

    private static func date(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: text)
    }
}

enum TraktError: Error {
    case notFound, privateProfile, badKey, network
}

/// Trakt API (yalnız okuma, herkese açık profil): kullanıcı adı ve Trakt uygulamasının Client ID'si.
/// Yanıtlar dışa aktarım dosyalarıyla aynı biçimde döner; aynı ayrıştırıcıdan geçer.
enum TraktAPI {
    private static let base = "https://api.trakt.tv/"

    @MainActor
    static func fetch(user: String, clientId: String, progress: @escaping (String) -> Void) async throws -> [(name: String, data: Data)] {
        let encoded = user.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        var files: [(name: String, data: Data)] = []
        // Geçmiş: sayfa sayfa.
        var page = 1
        var pageCount = 1
        var history: [Any] = []
        repeat {
            progress(L.traktFetchingHistory(page, pageCount))
            let (data, response) = try await get("users/\(encoded)/history?page=\(page)&limit=250", clientId: clientId)
            if let list = try? JSONSerialization.jsonObject(with: data) as? [Any] { history += list }
            pageCount = Int(response.value(forHTTPHeaderField: "X-Pagination-Page-Count") ?? "") ?? page
            page += 1
        } while page <= pageCount && page <= 200
        if !history.isEmpty, let data = try? JSONSerialization.data(withJSONObject: history) {
            files.append(("history.json", data))
        } else {
            // Geçmiş kapalıysa izlenenler (tarih yerine son izleme).
            progress(L.traktFetchingWatched)
            files.append(("watched-movies.json", try await get("users/\(encoded)/watched/movies", clientId: clientId).0))
            files.append(("watched-shows.json", try await get("users/\(encoded)/watched/shows", clientId: clientId).0))
        }
        progress(L.traktFetchingWatchlist)
        files.append(("watchlist.json", try await get("users/\(encoded)/watchlist", clientId: clientId).0))
        progress(L.traktFetchingLists)
        let listsData = try await get("users/\(encoded)/lists", clientId: clientId).0
        let lists = (try? JSONSerialization.jsonObject(with: listsData) as? [[String: Any]]) ?? []
        for list in lists.prefix(50) {
            guard let name = list["name"] as? String, let ids = list["ids"] as? [String: Any], let id = ids["trakt"] as? Int else { continue }
            let items = try await get("users/\(encoded)/lists/\(id)/items", clientId: clientId).0
            files.append(("lists-\(name).json", items))
        }
        return files
    }

    private static func get(_ path: String, clientId: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: base + path) else { throw TraktError.network }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientId, forHTTPHeaderField: "trakt-api-key")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw TraktError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TraktError.network }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 404: throw TraktError.notFound
        case 401, 403: throw http.value(forHTTPHeaderField: "X-Private-User") == "true" ? TraktError.privateProfile : TraktError.badKey
        case 412: throw TraktError.badKey
        default: throw TraktError.network
        }
    }
}

/// Eşleştirme ve uygulama: TMDB kimliği → IMDb `find` → ad araması; durumlar kendiliğinden
/// (izleme listesi İzleyeceğim, izlenen film Tamamladım, dizide bütün yayınlanmışlar izlendiyse Tamamladım
/// yoksa İzliyorum), listeler aynı adlı listeye.
@MainActor
final class TraktImportModel: ObservableObject {
    @Published var phase: String?
    @Published var fraction: Double?
    @Published var report: String?
    @Published var running = false

    func importFromTrakt(user: String, clientId: String, store: LibraryStore) async {
        await run(store) { [weak self] in
            try await TraktAPI.fetch(user: user, clientId: clientId) { text in self?.phase = text }
        }
    }

    func importFiles(_ urls: [URL], store: LibraryStore) async {
        await run(store) {
            var files: [(name: String, data: Data)] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                if ZipReader.isZip(data) {
                    files += ZipReader.files(data)
                } else {
                    files.append((url.lastPathComponent, data))
                }
            }
            return files
        }
    }

    private func run(_ store: LibraryStore, source: () async throws -> [(name: String, data: Data)]) async {
        running = true
        report = nil
        fraction = nil
        defer {
            running = false
            phase = nil
            fraction = nil
        }
        let files: [(name: String, data: Data)]
        do {
            files = try await source()
        } catch let error as TraktError {
            report = message(error)
            return
        } catch {
            report = L.traktErrorNetwork
            return
        }
        var items: [ImportItem] = []
        var ratings = 0
        for file in files {
            let parsed = TraktParser.parse(fileName: file.name, data: file.data)
            items += parsed.items
            ratings += parsed.ratings
        }
        guard !items.isEmpty else {
            report = L.traktNothing
            return
        }
        // Eşleştirme: her yapım bir kez.
        var refs: [String: MediaRef] = [:]
        var unmatched = Set<String>()
        let unique = Dictionary(items.map { ($0.matchKey, $0) }, uniquingKeysWith: { first, _ in first })
        var done = 0
        for (key, item) in unique {
            done += 1
            phase = L.traktMatching(done, unique.count)
            fraction = Double(done) / Double(max(unique.count, 1))
            if let ref = await match(item) { refs[key] = ref } else { unmatched.insert(item.title) }
        }
        var events: [WatchEvent] = []
        var titles: [String: TrackedTitle] = [:]
        var lists: [String: [MediaRef]] = [:]
        var showEpisodes: [Int: Set<EpisodeRef>] = [:]
        for item in items {
            guard let ref = refs[item.matchKey] else { continue }
            switch item.kind {
            case .watched:
                if ref.type == .tv {
                    guard let s = item.season, let e = item.episode else { continue }
                    events.append(WatchEvent(tmdbId: ref.tmdbId, type: .tv, season: s, episode: e, watchedAt: item.watchedAt ?? Date()))
                    showEpisodes[ref.tmdbId, default: []].insert(EpisodeRef(season: s, episode: e))
                } else {
                    events.append(WatchEvent(tmdbId: ref.tmdbId, type: .movie, season: nil, episode: nil, watchedAt: item.watchedAt ?? Date()))
                    titles[ref.id] = TrackedTitle(ref: ref, imdbId: item.imdbId, status: .COMPLETED, addedAt: item.watchedAt ?? Date())
                }
            case .watchlist:
                if titles[ref.id] == nil {
                    titles[ref.id] = TrackedTitle(ref: ref, imdbId: item.imdbId, status: .PLAN_TO_WATCH, addedAt: Date())
                }
            case .listItem:
                if let name = item.listName { lists[name, default: []].append(ref) }
            }
        }
        // Dizi durumları: bütün yayınlanmış bölümler izlendiyse Tamamladım.
        var index = 0
        for (tvId, watched) in showEpisodes {
            index += 1
            phase = L.traktStatuses(index, showEpisodes.count)
            fraction = Double(index) / Double(max(showEpisodes.count, 1))
            guard let ref = refs.values.first(where: { $0.type == .tv && $0.tmdbId == tvId }) else { continue }
            var status: TitleStatus = .WATCHING
            if let d = try? await TMDBClient.shared.detail(.tv, tvId) {
                let aired = NextEpisode.aired(seasons: d.regularSeasons, last: d.lastEpisodeToAir)
                let all = watched.union(store.watchedEpisodes(tvId))
                if !aired.isEmpty && aired.allSatisfy({ all.contains($0) }) { status = .COMPLETED }
            }
            titles[ref.id] = TrackedTitle(ref: ref, imdbId: nil, status: status, addedAt: Date())
        }
        let result = store.applyImport(events: events, titles: Array(titles.values), lists: lists)
        report = L.traktDone(result.events, result.titles, lists.count, unmatched.count, ratings)
    }

    private func match(_ item: ImportItem) async -> MediaRef? {
        if let tmdb = item.tmdbId {
            return MediaRef(tmdbId: tmdb, type: item.type, title: item.title, posterPath: nil, backdropPath: nil, year: item.year)
        }
        if let imdb = item.imdbId, let ref = try? await TMDBClient.shared.find(imdb: imdb) { return ref }
        guard !item.title.isEmpty else { return nil }
        return try? await TMDBClient.shared.match(item.type, name: item.title)
    }

    private func message(_ error: TraktError) -> String {
        switch error {
        case .notFound: return L.traktErrorNotFound
        case .privateProfile: return L.traktErrorPrivate
        case .badKey: return L.traktErrorKey
        case .network: return L.traktErrorNetwork
        }
    }
}

/// Ayarlar > Trakt'tan içe aktar: kullanıcı adıyla (Client ID gerekir) ya da dışa aktarım dosyasından (ZIP/JSON).
struct TraktImportView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var model = TraktImportModel()
    @AppStorage(SettingsKeys.traktUser) private var user = ""
    @AppStorage(SettingsKeys.traktClientId) private var clientId = ""
    @State private var picking = false

    var body: some View {
        Form {
            Section {
                TextField(L.traktUser, text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(L.traktClientId, text: $clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(L.traktImportButton) {
                    Task { await model.importFromTrakt(user: user, clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines), store: store) }
                }
                .disabled(model.running || user.trimmingCharacters(in: .whitespaces).isEmpty || clientId.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text(L.traktByUser)
            } footer: {
                Text(L.traktByUserHint)
            }
            Section {
                Button(L.traktPickFile) { picking = true }.disabled(model.running)
            } header: {
                Text(L.traktByFile)
            } footer: {
                Text(L.traktByFileHint)
            }
            if model.running || model.report != nil {
                Section {
                    if let phase = model.phase {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(phase).font(Theme.body(14)).foregroundStyle(Theme.text)
                            if let fraction = model.fraction {
                                ProgressView(value: fraction).tint(Theme.accent)
                            } else {
                                ProgressView().tint(Theme.accent)
                            }
                        }
                    }
                    if let report = model.report {
                        Text(report).font(Theme.body(14)).foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.traktImport)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip, .json], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importFiles(urls, store: store) }
        }
    }
}
