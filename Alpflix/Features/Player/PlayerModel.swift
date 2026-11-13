import Foundation
import MobileVLCKit
import SwiftUI

/// "Oynatma bilgisi" paneli: oynayan dosyanın teknik özeti.
struct PlaybackInfo: Equatable {
    var width: Int?
    var height: Int?
    var fps: Double?
    var videoCodec: String?
    var audioCodec: String?
    var audioChannels: Int?
    var audioRate: Int?
    var downloadKbps: Int?
    var displayed: Int = 0
    var lost: Int = 0
}

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
    /// Eklentilerin altyazı sonuçları (menüde durum satırı); nil: aranıyor.
    @Published var subtitleResults: [SubtitleResult]?
    @Published var rate: Float = 1
    @Published var next: (season: Int, episode: Int)?
    @Published var resolvingNext = false
    /// Şu an içinde bulunulan atlanabilir parça (giriş, özet, jenerik).
    @Published var skip: SkipSegment?
    /// Bölüm bitti, sıradaki bölüme geri sayım (sn).
    @Published var countdown: Int?
    /// Altyazı gecikmesi (ms; pozitif: altyazı geç gelir).
    @Published private(set) var subtitleDelayMs: Int = 0
    /// Basılı tutunca geçici 2x.
    @Published private(set) var boosting = false
    /// Duraklatınca gösterilen oyuncular (bölümde önce konuklar).
    @Published var cast: [TMDBCastMember] = []
    /// Ses gecikmesi (ms; pozitif: ses geç gelir).
    @Published private(set) var audioDelayMs: Int = 0
    /// Gece modu (konuşmalar öne çıkar, bas kısılır); kalıcı ayar.
    @Published private(set) var nightMode = UserDefaults.standard.bool(forKey: SettingsKeys.nightMode)
    /// Dokunmadan art arda bölümler oynadı: sıradaki başlamadan sorulur.
    @Published var stillWatching = false
    /// Açıksa oynatma bilgisi.
    @Published var info: PlaybackInfo?

    /// Kullanıcı dokunmadan kendiliğinden başlayan bölüm sayısı.
    private var autoEpisodes = 0
    private var lastReadBytes: Int32 = 0
    private var lastReadAt = Date.distantPast

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
        subtitleResults = nil
        audioTracks = []
        subtitleTracks = []
        next = nil
        segments = []
        dismissedSkips = []
        skip = nil
        countdownTask?.cancel()
        countdown = nil
        subtitleDelayMs = 0
        cast = []
        stillWatching = false
        applySubtitleStyle()
        let media = VLCMedia(url: request.url)
        media.addOption(":network-caching=3000")
        // Gece modu: VLC'nin sıkıştırıcısı (modül yoksa VLC filtreyi atlayıp oynatmaya devam eder).
        if nightMode {
            media.addOption(":audio-filter=compressor")
            media.addOption(":compressor-threshold=-24")
            media.addOption(":compressor-ratio=4")
            media.addOption(":compressor-makeup-gain=9")
        }
        if request.startMs > 0 { media.addOption(":start-time=\(request.startMs / 1000)") }
        player.media = media
        applyNightEqualizer()
        player.play()
        player.currentAudioPlaybackDelay = audioDelayMs * 1000
        Task { await loadExtras(request) }
    }

    /// Eklenti altyazıları ve (dizide) sıradaki bölüm.
    private func loadExtras(_ request: PlayRequest) async {
        guard let store else { return }
        Task { await loadCast(request) }
        let preferred = UserDefaults.standard.string(forKey: SettingsKeys.subtitleLanguage) ?? "tr"
        if request.url.isFileURL {
            // İndirilen yapım: altyazılar cihazda.
            externalSubtitles = request.localSubtitles
            subtitleResults = []
        } else {
            let id = AddonClient.stremioId(imdb: request.imdbId, season: request.season, episode: request.episode)
            // Dosyanın parmak izi: eklentiler bu sürüme ait (kaymayan) altyazıyı öne alır.
            let fingerprint = await VideoHash.fingerprint(request.url)
            guard self.request == request else { return }
            async let addonResults = AddonClient.allSubtitles(store.addons, type: request.ref.type.addonType, id: id, filename: request.filename, fingerprint: fingerprint)
            async let wyzie = WyzieClient.search(imdb: request.imdbId, season: request.season, episode: request.episode, preferred: preferred)
            var results = await addonResults
            let extra = await wyzie
            if let extra { results.append(extra) }
            guard self.request == request else { return }
            subtitleResults = results
            let subs = results.flatMap(\.items)
            externalSubtitles = subs.sorted { Self.matches($0.lang, preferred) && !Self.matches($1.lang, preferred) }
        }
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
        if info != nil { refreshInfo() }
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
            let limit = UserDefaults.standard.object(forKey: SettingsKeys.stillWatchingEpisodes) as? Int ?? 3
            if limit > 0 && self.autoEpisodes >= limit {
                self.stillWatching = true
                return
            }
            self.autoEpisodes += 1
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

    /// Kullanıcı ekrana dokundu: "Hâlâ izliyor musun?" sayacı sıfırlanır.
    func noteInteraction() {
        autoEpisodes = 0
    }

    /// "Hâlâ izliyor musun?" → Devam.
    func continueWatching() {
        stillWatching = false
        noteInteraction()
        Task { await playNext() }
    }

    func togglePlay() {
        noteInteraction()
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(toMs ms: Int64) {
        noteInteraction()
        player.time = VLCTime(int: Int32(clamping: max(0, ms)))
    }

    func jump(seconds: Int64) { seek(toMs: timeMs + seconds * 1000) }

    func setRate(_ value: Float) {
        rate = value
        player.rate = value
    }

    func selectAudio(_ id: Int32) { player.currentAudioTrackIndex = id }

    func setSubtitleDelay(_ ms: Int) {
        subtitleDelayMs = max(-10_000, min(10_000, ms))
        player.currentVideoSubTitleDelay = subtitleDelayMs * 1000
    }

    /// Ses gecikmesi (±3 sn, 50 ms adım); VLC mikrosaniye ister.
    func setAudioDelay(_ ms: Int) {
        audioDelayMs = max(-3_000, min(3_000, ms))
        player.currentAudioPlaybackDelay = audioDelayMs * 1000
    }

    /// Gece modu: ekolayzer hemen, sıkıştırıcı sıradaki yüklemede (VLC filtresi oynatma başında kurulur).
    func setNightMode(_ on: Bool) {
        nightMode = on
        UserDefaults.standard.set(on, forKey: SettingsKeys.nightMode)
        applyNightEqualizer()
    }

    /// Konuşma bandı (1–6 kHz) öne, bas geri; kapalıysa ekolayzer yok.
    private func applyNightEqualizer() {
        guard nightMode else {
            player.equalizer = nil
            return
        }
        let equalizer = VLCAudioEqualizer()
        equalizer.preAmplification = 4
        for band in equalizer.bands {
            band.amplification = Self.nightGain(frequency: band.frequency)
        }
        player.equalizer = equalizer
    }

    static func nightGain(frequency: Float) -> Float {
        switch frequency {
        case ..<100: return -8
        case ..<250: return -4
        case ..<800: return 0
        case ..<2_000: return 2
        case ..<7_000: return 5
        default: return 1
        }
    }

    /// Oynatma bilgisi panelini aç/kapat.
    func setInfoVisible(_ visible: Bool) {
        lastReadBytes = player.media?.statistics.readBytes ?? 0
        lastReadAt = Date()
        info = visible ? PlaybackInfo() : nil
        if visible { refreshInfo() }
    }

    private func refreshInfo() {
        guard let media = player.media else { return }
        var next = info ?? PlaybackInfo()
        let size = player.videoSize
        if size.width > 0 { next.width = Int(size.width); next.height = Int(size.height) }
        for case let track as [String: Any] in media.tracksInformation {
            let type = track[VLCMediaTracksInformationType] as? String
            let fourcc = (track[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value
            if type == VLCMediaTracksInformationTypeVideo {
                if let fourcc { next.videoCodec = VLCMedia.codecName(forFourCC: fourcc, trackType: VLCMediaTracksInformationTypeVideo) }
                let rate = (track[VLCMediaTracksInformationFrameRate] as? NSNumber)?.doubleValue ?? 0
                let denominator = (track[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber)?.doubleValue ?? 0
                if rate > 0 && denominator > 0 { next.fps = rate / denominator }
            } else if type == VLCMediaTracksInformationTypeAudio, next.audioCodec == nil {
                if let fourcc { next.audioCodec = VLCMedia.codecName(forFourCC: fourcc, trackType: VLCMediaTracksInformationTypeAudio) }
                next.audioChannels = (track[VLCMediaTracksInformationAudioChannelsNumber] as? NSNumber)?.intValue
                next.audioRate = (track[VLCMediaTracksInformationAudioRate] as? NSNumber)?.intValue
            }
        }
        let stats = media.statistics
        next.displayed = Int(stats.displayedPictures)
        next.lost = Int(stats.lostPictures)
        let elapsed = Date().timeIntervalSince(lastReadAt)
        if elapsed >= 1 {
            // readBytes 32 bit: 2 GB'ta başa sarar; o anki ölçüm atlanır.
            let delta = Int64(stats.readBytes) - Int64(lastReadBytes)
            if delta >= 0 { next.downloadKbps = Int(Double(delta) * 8 / 1000 / elapsed) }
            lastReadBytes = stats.readBytes
            lastReadAt = Date()
        }
        if next != info { info = next }
    }

    func setBoost(_ on: Bool) {
        guard on != boosting else { return }
        boosting = on
        player.rate = on ? max(2, rate) : rate
    }

    /// VLC ses düzeyi (0–200; 100 üstü yükseltme).
    var volume: Int32 {
        get { player.audio?.volume ?? 100 }
        set { player.audio?.volume = max(0, min(200, newValue)) }
    }

    /// Ayarlar'daki altyazı boyutu, rengi ve kalınlığı (VLC metin çizicisi; oynatma başlamadan).
    private func applySubtitleStyle() {
        let defaults = UserDefaults.standard
        let size = defaults.object(forKey: SettingsKeys.subtitleSize) as? Int ?? SubtitleStyle.defaultSize
        let color = defaults.object(forKey: SettingsKeys.subtitleColor) as? Int ?? SubtitleStyle.defaultColor
        let bold = defaults.bool(forKey: SettingsKeys.subtitleBold)
        perform("setTextRendererFontSize:", NSNumber(value: size))
        perform("setTextRendererFontColor:", NSNumber(value: color))
        perform("setTextRendererFontForceBold:", NSNumber(value: bold))
    }

    private func perform(_ name: String, _ value: NSNumber) {
        let selector = NSSelectorFromString(name)
        if player.responds(to: selector) { _ = player.perform(selector, with: value) }
    }

    private func loadCast(_ request: PlayRequest) async {
        let found: [TMDBCastMember]
        if let s = request.season, let e = request.episode {
            found = (try? await TMDBClient.shared.episodeCast(request.ref.tmdbId, season: s, episode: e)) ?? []
        } else {
            found = (try? await TMDBClient.shared.detail(request.ref.type, request.ref.tmdbId).credits?.cast) ?? []
        }
        guard self.request == request else { return }
        cast = Array(found.prefix(12))
    }

    func selectSubtitle(_ id: Int32) {
        autoSubtitleDone = true
        player.currentVideoSubTitleIndex = id
    }

    func selectExternal(_ subtitle: AddonSubtitle) {
        autoSubtitleDone = true
        guard let url = URL(string: subtitle.url), !addedSubtitles.contains(subtitle.url) else { return }
        addedSubtitles.insert(subtitle.url)
        Task {
            // Uzak adres önce cihaza .srt/.vtt olarak indirilir; indirilemezse adres doğrudan verilir.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("altyazi", isDirectory: true)
            let local = await SubtitleFiles.save(url, in: directory, name: UUID().uuidString) ?? url
            _ = player.addPlaybackSlave(local, type: .subtitle, enforce: true)
        }
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
        // Sıradaki bölüm indirildiyse internetsiz, dosyadan.
        if let local = DownloadStore.shared.playRequest(ref: request.ref, season: next.season, episode: next.episode, startMs: 0) {
            if !watchedRecorded { recordWatched() }
            player.stop()
            load(local)
            return
        }
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
            startMs: 0,
            filename: pick.stream.behaviorHints?.filename
        ))
    }
}
