import Foundation
import Network
import SwiftUI

enum DownloadState: String, Codable {
    case running, paused, done, failed
}

struct LocalSubtitleFile: Codable, Hashable {
    let lang: String?
    let fileName: String
}

/// İndirilen (ya da inmekte olan) bir film/bölüm. Dosyalar Application Support/Downloads'ta,
/// iCloud yedeğine girmez. Uzak adres (debrid bağlantısı) yalnız cihazda tutulur, gösterilmez.
struct DownloadItem: Codable, Identifiable, Hashable {
    let id: String
    let ref: MediaRef
    let imdbId: String
    let season: Int?
    let episode: Int?
    var episodeTitle: String?
    var sourceName: String
    var remoteURL: URL
    var fileName: String?
    var state: DownloadState
    var written: Int64
    var total: Int64
    var problem: String?
    var subtitles: [LocalSubtitleFile]
    var createdAt: Date

    var isEpisode: Bool { season != nil && episode != nil }
    var fraction: Double { total > 0 ? min(1, Double(written) / Double(total)) : 0 }

    static func key(_ ref: MediaRef, season: Int?, episode: Int?) -> String {
        if let season, let episode { return "\(ref.id):\(season):\(episode)" }
        return ref.id
    }
}

/// Arka plan indirmeleri (URLSession background): uygulama kapansa da sürer, yalnız Wi-Fi'de çalışır
/// (hücresel ve kısıtlı ağ kapalı; Wi-Fi gelene kadar bekler). Sezon indirmede kaynak kendiliğinden seçilir.
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()
    static let sessionIdentifier = "com.alpflix.ios.downloads"
    /// iOS uygulamayı arka planda indirme olayları için uyandırınca verdiği tamamlama.
    static var backgroundCompletion: (() -> Void)?

    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var wifi = true
    /// Sezon indirmede kaynak seçimi ilerlemesi (bitti, toplam).
    @Published private(set) var seasonJob: (done: Int, total: Int)?

    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    private let listFile = DownloadStore.directory.appendingPathComponent("downloads.json")
    private let delegate = DownloadDelegate()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForResource = 7 * 24 * 3600
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private var lastPublish: [String: Date] = [:]

    private init() {
        read()
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in DownloadStore.shared.wifi = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "alpflix.wifi"))
        session.getAllTasks { all in
            let downloads = all.compactMap { $0 as? URLSessionDownloadTask }
            Task { @MainActor in DownloadStore.shared.adopt(downloads) }
        }
    }

    // MARK: Sorgular

    func item(_ ref: MediaRef, season: Int?, episode: Int?) -> DownloadItem? {
        let key = DownloadItem.key(ref, season: season, episode: episode)
        return items.first { $0.id == key }
    }

    func fileURL(_ item: DownloadItem) -> URL? {
        guard item.state == .done, let name = item.fileName else { return nil }
        let url = Self.directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// İndirilmiş yapımın oynatma isteği (indirilmediyse nil).
    func playRequest(ref: MediaRef, season: Int?, episode: Int?, startMs: Int64) -> PlayRequest? {
        guard let item = item(ref, season: season, episode: episode) else { return nil }
        return playRequest(item, startMs: startMs)
    }

    func playRequest(_ item: DownloadItem, startMs: Int64) -> PlayRequest? {
        guard let url = fileURL(item) else { return nil }
        let subtitles = item.subtitles.map { file in
            AddonSubtitle(id: nil, url: Self.directory.appendingPathComponent(file.fileName).absoluteString, lang: file.lang)
        }
        return PlayRequest(
            ref: item.ref,
            imdbId: item.imdbId,
            season: item.season,
            episode: item.episode,
            episodeTitle: item.episodeTitle,
            url: url,
            bingeGroup: nil,
            startMs: startMs,
            localSubtitles: subtitles
        )
    }

    var usedBytes: Int64 { items.reduce(0) { $0 + ($1.state == .done ? $1.total : $1.written) } }

    var freeBytes: Int64 {
        let values = try? Self.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: İndirme başlatma

    /// Kaynağı sıraya ekler; hata metni döner (nil: eklendi).
    @discardableResult
    func enqueue(ref: MediaRef, imdbId: String, season: Int?, episode: Int?, episodeTitle: String?,
                 candidate: StreamCandidate, addons: [InstalledAddon]) -> String? {
        guard let url = candidate.playableURL, url.scheme?.hasPrefix("http") == true else { return L.downloadTorrent }
        let key = DownloadItem.key(ref, season: season, episode: episode)
        if let existing = items.first(where: { $0.id == key }), existing.state != .failed { return L.downloadExists }
        if let size = candidate.info.sizeGB, Int64(size * 1_073_741_824) + 500_000_000 > freeBytes { return L.downloadNoSpace }
        removeFiles(key)
        let item = DownloadItem(
            id: key,
            ref: ref,
            imdbId: imdbId,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle,
            sourceName: candidate.stream.behaviorHints?.filename ?? candidate.addonName,
            remoteURL: url,
            fileName: nil,
            state: .running,
            written: 0,
            total: Int64((candidate.info.sizeGB ?? 0) * 1_073_741_824),
            problem: nil,
            subtitles: [],
            createdAt: Date()
        )
        items.removeAll { $0.id == key }
        items.insert(item, at: 0)
        save()
        start(item, resumeData: nil)
        Task { await fetchSubtitles(item, filename: candidate.stream.behaviorHints?.filename, addons: addons) }
        return nil
    }

    /// Sezonun yayınlanmış ve henüz indirilmemiş bölümleri: her biri için kaynak seçilir (ilk seçilenin
    /// sürüm grubu önce, sonra hazır/yüksek çözünürlüklü), sırayla eklenir. (eklenen, bulunamayan) döner.
    func enqueueSeason(ref: MediaRef, imdbId: String, episodes: [TMDBEpisode], addons: [InstalledAddon]) async -> (added: Int, missing: Int) {
        let wanted = episodes.filter { e in
            e.hasAired && (item(ref, season: e.seasonNumber, episode: e.episodeNumber).map { $0.state == .failed } ?? true)
        }
        guard !wanted.isEmpty else { return (0, 0) }
        seasonJob = (0, wanted.count)
        defer { seasonJob = nil }
        var added = 0
        var missing = 0
        var group: String?
        for (index, e) in wanted.enumerated() {
            let id = AddonClient.stremioId(imdb: imdbId, season: e.seasonNumber, episode: e.episodeNumber)
            let candidates = await AddonClient.allStreams(addons, type: "series", id: id)
                .filter { $0.playableURL?.scheme?.hasPrefix("http") == true && !$0.info.torrentOnly }
            let pick = candidates.first { group != nil && $0.stream.behaviorHints?.bingeGroup == group }
                ?? candidates.first { $0.info.cached }
                ?? candidates.first
            if let pick, enqueue(ref: ref, imdbId: imdbId, season: e.seasonNumber, episode: e.episodeNumber,
                                 episodeTitle: e.name, candidate: pick, addons: addons) == nil {
                added += 1
                if group == nil { group = pick.stream.behaviorHints?.bingeGroup }
            } else {
                missing += 1
            }
            seasonJob = (index + 1, wanted.count)
        }
        return (added, missing)
    }

    // MARK: Denetimler

    func pause(_ item: DownloadItem) {
        let id = item.id
        guard let task = tasks[id] else { return }
        tasks[id] = nil
        task.cancel(byProducingResumeData: { data in
            Task { @MainActor in
                let store = DownloadStore.shared
                if let data { try? data.write(to: store.resumeFile(id)) }
                store.update(id) { $0.state = .paused }
            }
        })
    }

    func resume(_ item: DownloadItem) {
        let data = try? Data(contentsOf: resumeFile(item.id))
        try? FileManager.default.removeItem(at: resumeFile(item.id))
        update(item.id) {
            $0.state = .running
            $0.problem = nil
        }
        start(item, resumeData: data)
    }

    func delete(_ item: DownloadItem) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        removeFiles(item.id)
        items.removeAll { $0.id == item.id }
        save()
    }

    // MARK: İç işleyiş

    private func start(_ item: DownloadItem, resumeData: Data?) {
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: item.remoteURL)
        task.taskDescription = item.id
        tasks[item.id] = task
        task.resume()
    }

    private func adopt(_ running: [URLSessionDownloadTask]) {
        for task in running {
            guard let id = task.taskDescription, items.contains(where: { $0.id == id }) else {
                task.cancel()
                continue
            }
            tasks[id] = task
        }
        // Uygulama kapalıyken iptal olanlar: kaldığı yerden sürdürülebilir.
        for item in items where item.state == .running && tasks[item.id] == nil {
            update(item.id) { $0.state = .paused }
        }
    }

    private func fetchSubtitles(_ item: DownloadItem, filename: String?, addons: [InstalledAddon]) async {
        let preferred = UserDefaults.standard.string(forKey: SettingsKeys.subtitleLanguage) ?? "tr"
        let id = AddonClient.stremioId(imdb: item.imdbId, season: item.season, episode: item.episode)
        let all = await AddonClient.allSubtitles(addons, type: item.ref.type.addonType, id: id, filename: filename).flatMap(\.items)
        var chosen: [AddonSubtitle] = []
        for language in [preferred, "en"] where language != "none" {
            let taken = chosen
            let picks = all.filter { PlayerModel.matches($0.lang, language) && !taken.contains($0) }.prefix(2)
            chosen.append(contentsOf: picks)
        }
        var files: [LocalSubtitleFile] = []
        for (index, sub) in chosen.prefix(4).enumerated() {
            guard let url = URL(string: sub.url),
                  let saved = await SubtitleFiles.save(url, in: Self.directory, name: "\(Self.safeName(item.id))-sub\(index)") else { continue }
            files.append(LocalSubtitleFile(lang: sub.lang, fileName: saved.lastPathComponent))
        }
        update(item.id) { $0.subtitles = files }
    }

    fileprivate func progress(_ id: String, written: Int64, total: Int64) {
        let now = Date()
        if let last = lastPublish[id], now.timeIntervalSince(last) < 1 { return }
        lastPublish[id] = now
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].written = written
        if total > 0 { items[index].total = total }
    }

    fileprivate func finished(_ id: String, fileName: String?, size: Int64, problem: String?) {
        tasks[id] = nil
        update(id) {
            if let fileName {
                $0.fileName = fileName
                $0.state = .done
                $0.written = size
                $0.total = size
                $0.problem = nil
            } else {
                $0.state = .failed
                $0.problem = problem ?? L.downloadFailed
            }
        }
    }

    fileprivate func failed(_ id: String, resumeData: Data?) {
        tasks[id] = nil
        if let resumeData { try? resumeData.write(to: resumeFile(id)) }
        update(id) {
            guard $0.state == .running else { return }
            $0.state = resumeData != nil ? .paused : .failed
            $0.problem = resumeData != nil ? nil : L.downloadFailed
        }
    }

    private func update(_ id: String, _ change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    private func resumeFile(_ id: String) -> URL {
        Self.directory.appendingPathComponent("\(Self.safeName(id)).resume")
    }

    private func removeFiles(_ id: String) {
        let prefix = Self.safeName(id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) ?? []
        for name in names where name.hasPrefix(prefix + ".") || name.hasPrefix(prefix + "-sub") {
            try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(name))
        }
    }

    nonisolated static func safeName(_ id: String) -> String {
        id.replacingOccurrences(of: ":", with: "_")
    }

    private func read() {
        guard let data = try? Data(contentsOf: listFile),
              let list = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: listFile, options: .atomic)
    }

    /// Debrid'in "indiriliyor / başarısız" uyarı videosu (Torrentio, MediaFusion).
    nonisolated static func isPlaceholder(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased(), path.hasSuffix(".mp4") else { return false }
        return ["/videos/", "/static/exceptions/", "/static/videos/"].contains { path.contains($0) }
    }
}

/// URLSession olayları: dosya geçici yerden hemen (olay dönmeden) indirme klasörüne taşınır.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in DownloadStore.shared.progress(id, written: totalBytesWritten, total: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let response = downloadTask.response as? HTTPURLResponse
        let size = Int64((try? location.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        var fileName: String?
        var problem: String?
        if let status = response?.statusCode, !(200..<300).contains(status) {
            problem = L.downloadFailed
        } else if DownloadStore.isPlaceholder(response?.url) || size < 20_000_000 {
            problem = L.downloadPlaceholder
        } else {
            let ext = Self.fileExtension(response)
            let name = "\(DownloadStore.safeName(id)).\(ext)"
            let target = DownloadStore.directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            do {
                try FileManager.default.moveItem(at: location, to: target)
                fileName = name
            } catch {
                problem = L.downloadFailed
            }
        }
        Task { @MainActor in DownloadStore.shared.finished(id, fileName: fileName, size: size, problem: problem) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if (error as? URLError)?.code == .cancelled && resumeData == nil { return }
        Task { @MainActor in DownloadStore.shared.failed(id, resumeData: resumeData) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            DownloadStore.backgroundCompletion?()
            DownloadStore.backgroundCompletion = nil
        }
    }

    private static func fileExtension(_ response: HTTPURLResponse?) -> String {
        let known = ["mkv", "mp4", "m4v", "avi", "mov", "webm", "ts"]
        let candidates = [response?.suggestedFilename, response?.url?.lastPathComponent]
        for name in candidates.compactMap({ $0 }) {
            let ext = (name as NSString).pathExtension.lowercased()
            if known.contains(ext) { return ext }
        }
        return "mkv"
    }
}
