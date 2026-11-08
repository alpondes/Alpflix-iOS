import Foundation
import SwiftUI

/// Bütün kullanıcı verisi: cihazda tek JSON dosyası (Application Support/alpflix.json). Hesap yok, sunucu yok.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var data = AppData()

    private var fileURL: URL

    private var saveTask: Task<Void, Never>?

    /// Profilin veri dosyası (Application Support).
    nonisolated static func fileURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    init(fileName: String = "alpflix.json") {
        fileURL = Self.fileURL(fileName)
        read()
    }

    /// Başka profilin dosyasına geçer: bekleyen yazma hemen yapılır, yeni dosya okunur.
    func load(fileName: String) {
        saveTask?.cancel()
        if let bytes = try? JSONEncoder().encode(data) { try? bytes.write(to: fileURL, options: .atomic) }
        fileURL = Self.fileURL(fileName)
        data = AppData()
        read()
    }

    private func read() {
        guard let bytes = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode(AppData.self, from: bytes) {
            data = decoded
        } else {
            // Okunamayan dosya üzerine yazılmasın: kenara alınır.
            try? bytes.write(to: fileURL.deletingLastPathComponent().appendingPathComponent("alpflix-okunamayan-\(Int(Date().timeIntervalSince1970)).json"))
        }
    }

    private func mutate(_ change: (inout AppData) -> Void) {
        change(&data)
        scheduleSave()
    }

    /// Kısa bekleyip diske yazar (art arda değişikliklerde tek yazma).
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            if let bytes = try? JSONEncoder().encode(snapshot) { try? bytes.write(to: url, options: .atomic) }
        }
    }

    // MARK: Kütüphane

    func tracked(_ ref: MediaRef) -> TrackedTitle? { data.titles[ref.id] }

    func status(_ ref: MediaRef) -> TitleStatus? { data.titles[ref.id]?.status }

    func setStatus(_ ref: MediaRef, _ status: TitleStatus?, imdbId: String? = nil) {
        mutate { d in
            if status == nil {
                d.titles[ref.id] = nil
            } else {
                var entry = d.titles[ref.id] ?? TrackedTitle(ref: ref, imdbId: imdbId, status: nil, addedAt: Date())
                entry.status = status
                entry.ref = merged(entry.ref, ref)
                if let imdbId { entry.imdbId = imdbId }
                d.titles[ref.id] = entry
            }
        }
    }

    func titles(with status: TitleStatus) -> [TrackedTitle] {
        data.titles.values.filter { $0.status == status }.sorted { $0.addedAt > $1.addedAt }
    }

    /// Kart bilgisi eksikse (yedekten gelen) TMDB'den gelenle tamamlar.
    func updateRef(_ ref: MediaRef) {
        guard let existing = data.titles[ref.id] else { return }
        let next = merged(existing.ref, ref)
        guard next != existing.ref else { return }
        mutate { $0.titles[ref.id]?.ref = next }
    }

    private func merged(_ old: MediaRef, _ new: MediaRef) -> MediaRef {
        MediaRef(
            tmdbId: old.tmdbId,
            type: old.type,
            title: new.title.isEmpty ? old.title : new.title,
            posterPath: new.posterPath ?? old.posterPath,
            backdropPath: new.backdropPath ?? old.backdropPath,
            year: new.year ?? old.year
        )
    }

    // MARK: İzleme geçmişi

    func isMovieWatched(_ id: Int) -> Bool {
        data.events.contains { $0.type == .movie && $0.tmdbId == id }
    }

    func watchedEpisodes(_ tvId: Int) -> Set<EpisodeRef> {
        Set(data.events.compactMap { (e: WatchEvent) -> EpisodeRef? in
            guard e.type == .tv, e.tmdbId == tvId, let s = e.season, let n = e.episode else { return nil }
            return EpisodeRef(season: s, episode: n)
        })
    }

    /// Film ya da bölüm izlendi / izlenmedi. Bölüm izlenince "İzleyeceğim" / "Beklemede" dizi "İzliyorum" olur.
    func setWatched(_ ref: MediaRef, season: Int? = nil, episode: Int? = nil, watched: Bool, imdbId: String? = nil) {
        mutate { d in
            if watched {
                d.events.append(WatchEvent(tmdbId: ref.tmdbId, type: ref.type, season: season, episode: episode, watchedAt: Date()))
                d.progress[PlaybackProgress.key(ref.tmdbId, ref.type, season, episode)] = nil
                var entry = d.titles[ref.id] ?? TrackedTitle(ref: ref, imdbId: imdbId, status: nil, addedAt: Date())
                if ref.type == .movie {
                    entry.status = .COMPLETED
                } else if entry.status == nil || entry.status == .PLAN_TO_WATCH || entry.status == .ON_HOLD {
                    entry.status = .WATCHING
                }
                if let imdbId { entry.imdbId = imdbId }
                d.titles[ref.id] = entry
            } else {
                d.events.removeAll { $0.tmdbId == ref.tmdbId && $0.type == ref.type && $0.season == season && $0.episode == episode }
            }
        }
    }

    /// Dizinin bütün yayınlanmış bölümleri izlendiyse "Bitti".
    func refreshSeriesStatus(_ ref: MediaRef, aired: [EpisodeRef]) {
        guard ref.type == .tv, !aired.isEmpty else { return }
        let watched = watchedEpisodes(ref.tmdbId)
        guard aired.allSatisfy({ watched.contains($0) }), status(ref) != .DROPPED, status(ref) != .COMPLETED else { return }
        setStatus(ref, .COMPLETED)
    }

    func lastWatched(_ tvId: Int) -> Date? {
        data.events.filter { $0.type == .tv && $0.tmdbId == tvId }.map(\.watchedAt).max()
    }

    // MARK: Kaldığın yer

    func progress(_ ref: MediaRef, season: Int?, episode: Int?) -> PlaybackProgress? {
        data.progress[PlaybackProgress.key(ref.tmdbId, ref.type, season, episode)]
    }

    func saveProgress(_ ref: MediaRef, imdbId: String?, season: Int?, episode: Int?, positionMs: Int64, durationMs: Int64) {
        guard durationMs > 0 else { return }
        mutate { d in
            let item = PlaybackProgress(ref: ref, imdbId: imdbId, season: season, episode: episode, positionMs: positionMs, durationMs: durationMs, updatedAt: Date())
            d.progress[item.key] = item
        }
    }

    // MARK: İzlemeye devam et

    func dismissContinue(_ key: String) { mutate { $0.dismissedContinue[key] = Date() } }

    func undoDismissContinue(_ key: String) { mutate { $0.dismissedContinue[key] = nil } }

    /// Yarım kalanlar (son kayıt yarımdan yeniyse eskimiş sayılır).
    func resumeItems() -> [PlaybackProgress] {
        data.progress.values.filter { p in
            guard p.fraction > 0.02, p.fraction < 0.95 else { return false }
            let lastEvent = data.events.filter { $0.tmdbId == p.ref.tmdbId && $0.type == p.ref.type }.map(\.watchedAt).max()
            if let lastEvent, lastEvent >= p.updatedAt { return false }
            if let dismissed = data.dismissedContinue[p.ref.id], dismissed >= p.updatedAt { return false }
            return true
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Son 30 günde bölümü izlenen diziler ("Bıraktım" hariç), en son izlenen önce.
    func recentSeries() -> [(MediaRef, Date)] {
        let since = Date().addingTimeInterval(-30 * 24 * 3600)
        var latest: [Int: Date] = [:]
        for e in data.events where e.type == .tv && e.watchedAt >= since {
            latest[e.tmdbId] = max(latest[e.tmdbId] ?? .distantPast, e.watchedAt)
        }
        return latest.compactMap { (entry: (key: Int, value: Date)) -> (MediaRef, Date)? in
            let id = entry.key
            let at = entry.value
            let key = "tv:\(id)"
            if data.titles[key]?.status == .DROPPED { return nil }
            if let dismissed = data.dismissedContinue[key], dismissed >= at { return nil }
            let ref = data.titles[key]?.ref ?? MediaRef(tmdbId: id, type: .tv, title: "", posterPath: nil, backdropPath: nil, year: nil)
            return (ref, at)
        }.sorted { $0.1 > $1.1 }
    }

    // MARK: Hatırlatıcılar

    /// Günü geçmemiş hatırlatıcılar, tarihe göre.
    var reminders: [Reminder] {
        let start = Calendar.current.startOfDay(for: Date())
        return data.reminders.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }

    func hasReminder(_ id: String) -> Bool { data.reminders.contains { $0.id == id } }

    /// Varsa kaldırır, yoksa kurar (bildirim izni ilk seferde istenir). Kurulduysa true.
    @discardableResult
    func toggleReminder(_ reminder: Reminder) async -> Bool {
        if hasReminder(reminder.id) {
            ReminderScheduler.cancel(reminder)
            mutate { $0.reminders.removeAll { $0.id == reminder.id } }
            return false
        }
        _ = await ReminderScheduler.requestPermission()
        ReminderScheduler.schedule(reminder)
        let start = Calendar.current.startOfDay(for: Date())
        mutate { d in
            d.reminders.removeAll { $0.date < start }
            d.reminders.append(reminder)
        }
        return true
    }

    // MARK: Eklentiler

    var addons: [InstalledAddon] { data.addons }

    func addAddon(_ addon: InstalledAddon) {
        mutate { d in
            d.addons.removeAll { $0.manifestUrl == addon.manifestUrl }
            d.addons.append(addon)
        }
    }

    func removeAddon(_ addon: InstalledAddon) { mutate { $0.addons.removeAll { $0.manifestUrl == addon.manifestUrl } } }

    func setAddonEnabled(_ addon: InstalledAddon, _ enabled: Bool) {
        mutate { d in
            if let i = d.addons.firstIndex(where: { $0.manifestUrl == addon.manifestUrl }) { d.addons[i].enabled = enabled }
        }
    }

    func moveAddons(from: IndexSet, to: Int) { mutate { $0.addons.move(fromOffsets: from, toOffset: to) } }

    // MARK: Yedek aktarımı

    /// Android yedeğinden gelenleri birleştirir (var olanlar korunur, yeni gelenler eklenir).
    func merge(_ imported: AppData) {
        mutate { d in
            for (key, title) in imported.titles where d.titles[key] == nil { d.titles[key] = title }
            let existing = Set(d.events.map { "\($0.type.rawValue):\($0.tmdbId):\($0.season ?? 0):\($0.episode ?? 0):\(Int($0.watchedAt.timeIntervalSince1970))" })
            d.events += imported.events.filter {
                !existing.contains("\($0.type.rawValue):\($0.tmdbId):\($0.season ?? 0):\($0.episode ?? 0):\(Int($0.watchedAt.timeIntervalSince1970))")
            }
            for (key, p) in imported.progress where (d.progress[key]?.updatedAt ?? .distantPast) < p.updatedAt { d.progress[key] = p }
            for addon in imported.addons where !d.addons.contains(where: { $0.manifestUrl == addon.manifestUrl }) { d.addons.append(addon) }
        }
    }
}
