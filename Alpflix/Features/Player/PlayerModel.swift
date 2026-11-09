import Foundation
import MobileVLCKit
import SwiftUI

struct TrackChoice: Identifiable, Hashable {
    let id: Int32
    let name: String
}

/// VLC tabanlı oynatıcı (MKV, HEVC, gömülü altyazı). Durum yarım saniyede bir okunur; kaldığın yer
/// 10 saniyede bir kaydedilir, %90'da izlendi sayılır.
@MainActor
final class PlayerModel: ObservableObject {
    let player = VLCMediaPlayer()

    @Published private(set) var request: PlayRequest
    @Published var playing = false
    @Published var buffering = true
    @Published var failed = false
    @Published var ended = false
    @Published var timeMs: Int64 = 0
    @Published var lengthMs: Int64 = 0
    @Published var audioTracks: [TrackChoice] = []
    @Published var subtitleTracks: [TrackChoice] = []
    @Published var currentAudio: Int32 = -1
    @Published var currentSubtitle: Int32 = -1
    @Published var externalSubtitles: [AddonSubtitle] = []
    @Published var rate: Float = 1
    @Published var next: (season: Int, episode: Int)?
    @Published var resolvingNext = false
    /// Şu an içinde bulunulan atlanabilir parça (giriş, özet, jenerik).
    @Published var skip: SkipSegment?
    /// Bölüm bitti, sıradaki bölüme geri sayım (sn).
    @Published var countdown: Int?

    private var segments: [SkipSegment] = []
    private var dismissedSkips: Set<SkipKind> = []
    private var countdownTask: Task<Void, Never>?

    private weak var store: LibraryStore?
    private var timer: Timer?
    private var lastSaveAt = Date.distantPast
    private var watchedRecorded = false
    private var autoSubtitleDone = false
    /// Zamanın ilerlemediği art arda yoklama sayısı (takılma göstergesi için).
    private var stallTicks = 0
    private var addedSubtitles: Set<String> = []

    init(request: PlayRequest) {
        self.request = request
    }

    func start(store: LibraryStore) {
        self.store = store
        load(request)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        countdownTask?.cancel()
        saveProgress(force: true)
        timer?.invalidate()
        timer = nil
        player.stop()
    }

    private func load(_ request: PlayRequest) {
        self.request = request
        failed = false
        ended = false
        buffering = true
        timeMs = 0
        stallTicks = 0
        watchedRecorded = false
        autoSubtitleDone = false
        addedSubtitles = []
        externalSubtitles = []
        audioTracks = []
        subtitleTracks = []
        next = nil
        segments = []
        dismissedSkips = []
        skip = nil
        countdownTask?.cancel()
        countdown = nil
        let media = VLCMedia(url: request.url)
        media.addOption(":network-caching=3000")
        if request.startMs > 0 { media.addOption(":start-time=\(request.startMs / 1000)") }
        player.media = media
        player.play()
        Task { await loadExtras(request) }
    }

    /// Eklenti altyazıları ve (dizide) sıradaki bölüm.
    private func loadExtras(_ request: PlayRequest) async {
        guard let store else { return }
        let id = AddonClient.stremioId(imdb: request.imdbId, season: request.season, episode: request.episode)
        let subs = await AddonClient.allSubtitles(store.addons, type: request.ref.type.addonType, id: id)
        let preferred = UserDefaults.standard.string(forKey: SettingsKeys.subtitleLanguage) ?? "tr"
        externalSubtitles = subs.sorted { Self.matches($0.lang, preferred) && !Self.matches($1.lang, preferred) }
        if let url = SkipSegments.url(tmdbId: request.ref.tmdbId, season: request.season, episode: request.episode),
           let data = try? await HTTP.data(url, timeout: 10) {
            segments = SkipSegments.parse(data, season: request.season, episode: request.episode)
        }
        if let s = request.season, let e = request.episode,
           let detail = try? await TMDBClient.shared.detail(.tv, request.ref.tmdbId) {
            let aired = NextEpisode.aired(seasons: detail.regularSeasons, last: detail.lastEpisodeToAir)
            if let n = aired.first(where: { $0 > EpisodeRef(season: s, episode: e) }) { next = (n.season, n.episode) }
        }
    }

    static func matches(_ language: String?, _ preferred: String) -> Bool {
        guard let lang = language?.lowercased() else { return false }
        if preferred == "tr" { return lang.hasPrefix("tr") || lang.contains("turk") || lang.contains("türk") }
        return lang.hasPrefix(preferred)
    }

    private func tick() {
        let state = player.state
        playing = player.isPlaying
        // VLCKit oynarken de durumu "buffering" bildirebiliyor; gösterge zamanın ilerleyip
        // ilerlemediğine bakar: başta zaman 0 iken ya da 1 sn'den uzun takılmada görünür.
        let newTime = Int64(player.time.intValue)
        let advancing = newTime != timeMs
        let loading = state != .paused && state != .stopped && state != .ended && state != .error
        if advancing || !loading { stallTicks = 0 } else { stallTicks += 1 }
        let waiting = loading && !advancing && (newTime <= 0 || stallTicks >= 2)
        if waiting != buffering { buffering = waiting }
        if state == .error { failed = true }
        if state == .ended && !ended {
            ended = true
            startCountdown()
        }
        timeMs = newTime
        lengthMs = Int64(player.media?.length.intValue ?? 0)
        refreshTracks()
        autoSelectSubtitle()
        saveProgress(force: false)
        if lengthMs > 0 {
            let threshold = min(Int64(Double(lengthMs) * 0.9), SkipSegments.creditsStart(segments, duration: lengthMs) ?? lengthMs)
            if timeMs >= threshold { recordWatched() }
        }
        let active = SkipSegments.active(segments, position: timeMs, duration: lengthMs)
        let shown = active.flatMap { dismissedSkips.contains($0.kind) ? nil : $0 }
        if shown != skip { skip = shown }
    }

    /// Parçayı atla: jenerik/önizlemede sıradaki bölüm varsa ona geçilir, yoksa parçanın sonuna.
    func skipSegment() {
        guard let skip else { return }
        dismissedSkips.insert(skip.kind)
        self.skip = nil
        if (skip.kind == .credits || skip.kind == .preview) && next != nil {
            Task { await playNext() }
            return
        }
        seek(toMs: min(skip.end(lengthMs), max(lengthMs - 500, 0)))
    }

    /// Bölüm bitti: ayar açıksa 5 sn geri sayımla sıradaki bölüm.
    private func startCountdown() {
        let auto = UserDefaults.standard.object(forKey: SettingsKeys.autoPlayNext) as? Bool ?? true
        guard auto, next != nil, request.isEpisode else { return }
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: 5, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.countdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.countdown = nil
            await self.playNext()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdown = nil
    }

    private func refreshTracks() {
        let audio = Self.choices(player.audioTrackIndexes, player.audioTrackNames)
        if audio != audioTracks { audioTracks = audio }
        let subs = Self.choices(player.videoSubTitlesIndexes, player.videoSubTitlesNames)
        if subs != subtitleTracks { subtitleTracks = subs }
        currentAudio = player.currentAudioTrackIndex
        currentSubtitle = player.currentVideoSubTitleIndex
    }

    private static func choices(_ indexes: [Any], _ names: [Any]) -> [TrackChoice] {
        zip(indexes, names).compactMap { (index, name) -> TrackChoice? in
            guard let number = index as? NSNumber else { return nil }
            let id = number.int32Value
            return TrackChoice(id: id, name: (name as? String) ?? "\(id)")
        }
    }

    /// Videoda tercih edilen dilde altyazı yoksa eklentiden gelen ilk uygun altyazı açılır (bir kez).
    private func autoSelectSubtitle() {
        guard !autoSubtitleDone, playing, !externalSubtitles.isEmpty else { return }
        let preferred = UserDefaults.standard.string(forKey: SettingsKeys.subtitleLanguage) ?? "tr"
        autoSubtitleDone = true
        guard preferred != "none" else { return }
        if subtitleTracks.contains(where: { $0.id >= 0 && Self.matches($0.name, preferred) }) { return }
        if let match = externalSubtitles.first(where: { Self.matches($0.lang, preferred) }) { selectExternal(match) }
    }

    // MARK: Denetimler

    func togglePlay() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(toMs ms: Int64) {
        player.time = VLCTime(int: Int32(clamping: max(0, ms)))
    }

    func jump(seconds: Int64) { seek(toMs: timeMs + seconds * 1000) }

    func setRate(_ value: Float) {
        rate = value
        player.rate = value
    }

    func selectAudio(_ id: Int32) { player.currentAudioTrackIndex = id }

    func selectSubtitle(_ id: Int32) {
        autoSubtitleDone = true
        player.currentVideoSubTitleIndex = id
    }

    func selectExternal(_ subtitle: AddonSubtitle) {
        autoSubtitleDone = true
        guard let url = URL(string: subtitle.url), !addedSubtitles.contains(subtitle.url) else { return }
        addedSubtitles.insert(subtitle.url)
        _ = player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    // MARK: Kayıt

    private func saveProgress(force: Bool) {
        guard let store, lengthMs > 0, timeMs > 0, !watchedRecorded else { return }
        guard force || Date().timeIntervalSince(lastSaveAt) >= 10 else { return }
        lastSaveAt = Date()
        store.saveProgress(request.ref, imdbId: request.imdbId, season: request.season, episode: request.episode, positionMs: timeMs, durationMs: lengthMs)
    }

    private func recordWatched() {
        guard !watchedRecorded, let store else { return }
        watchedRecorded = true
        store.setWatched(request.ref, season: request.season, episode: request.episode, watched: true, imdbId: request.imdbId)
    }

    // MARK: Sıradaki bölüm

    /// Sıradaki bölümün kaynağı: aynı sürüm grubu (bingeGroup) önce, yoksa en iyi sıradaki kaynak.
    func playNext() async {
        guard let next, let store else { return }
        resolvingNext = true
        defer { resolvingNext = false }
        let id = AddonClient.stremioId(imdb: request.imdbId, season: next.season, episode: next.episode)
        let candidates = await AddonClient.allStreams(store.addons, type: "series", id: id).filter { $0.playableURL != nil }
        let pick = candidates.first { request.bingeGroup != nil && $0.stream.behaviorHints?.bingeGroup == request.bingeGroup } ?? candidates.first
        guard let pick, let url = pick.playableURL else {
            failed = true
            return
        }
        if !watchedRecorded { recordWatched() }
        player.stop()
        load(PlayRequest(
            ref: request.ref,
            imdbId: request.imdbId,
            season: next.season,
            episode: next.episode,
            episodeTitle: nil,
            url: url,
            bingeGroup: pick.stream.behaviorHints?.bingeGroup,
            startMs: 0
        ))
    }
}
