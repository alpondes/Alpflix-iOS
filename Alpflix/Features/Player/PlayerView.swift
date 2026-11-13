import MobileVLCKit
import SwiftUI

/// VLC görüntüsünün çizildiği görünüm.
struct VLCVideoView: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Tam ekran oynatıcı: dokununca denetimler; yatay kilit; ekran kararmaz.
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var model: PlayerModel
    @State private var controls = true
    /// Açık seçim paneli (ses / altyazı). Açıkken denetimler gizlenmez; panel denetimlerden bağımsızdır.
    @State private var panel: PlayerPanel?
    @GestureState private var holding = false
    /// Kaydırma göstergesi: (simge, yüzde).
    @State private var swipeIndicator: (icon: String, percent: Int)?
    @State private var swipeStart: (value: Double, isVolume: Bool)?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?
    /// İki parmakla yakınlaştırma (1x–3x).
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    init(request: PlayRequest) {
        _model = StateObject(wrappedValue: PlayerModel(request: request))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCVideoView(player: model.player)
                .scaleEffect(min(3, max(1, zoom * pinch)))
                .ignoresSafeArea()
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                    // Solda yukarı/aşağı: parlaklık; sağda: ses.
                    .gesture(
                        DragGesture(minimumDistance: 14)
                            .onChanged { value in swipe(value, size: geo.size) }
                            .onEnded { _ in
                                swipeStart = nil
                                withAnimation(.easeOut(duration: 0.2)) { swipeIndicator = nil }
                            }
                    )
                    // İki parmak: yakınlaştırma.
                    .simultaneousGesture(
                        MagnificationGesture()
                            .updating($pinch) { value, state, _ in state = value }
                            .onEnded { value in
                                zoom = min(3, max(1, zoom * value))
                                model.noteInteraction()
                            }
                    )
                    // Basılı tut: 2x.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .updating($holding) { value, state, _ in
                                if case .second(true, _) = value { state = true }
                            }
                    )
            }
            .ignoresSafeArea()
            if model.boosting {
                VStack {
                    Label(L.playerBoost, systemImage: "forward.fill")
                        .font(Theme.mono(13).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.surface.opacity(0.9), in: Capsule())
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.top, 24)
                .allowsHitTesting(false)
            }
            if let indicator = swipeIndicator {
                Label("\(indicator.percent)%", systemImage: indicator.icon)
                    .font(Theme.mono(16).weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface.opacity(0.9), in: Capsule())
                    .foregroundStyle(Theme.text)
                    .allowsHitTesting(false)
            }
            if !model.playing && !model.buffering && !model.failed && model.countdown == nil && !model.cast.isEmpty && panel == nil {
                pausedCast
            }
            if let info = model.info {
                VStack {
                    HStack {
                        infoOverlay(info)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 70)
                .padding(.leading, 20)
            }
            if model.buffering && !model.failed {
                ProgressView().tint(Theme.accent).scaleEffect(1.4)
            }
            if model.failed {
                MessageView(text: L.playerFailed)
                    .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    .padding(40)
            }
            if controls { overlay }
            // Giriş/özet/jenerik atlama: denetimler gizliyken de görünür.
            if let skip = model.skip, model.countdown == nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { model.skipSegment() } label: {
                            Label(skip.kind.label, systemImage: "forward.fill")
                                .font(Theme.body(16).weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Theme.surface.opacity(0.92), in: Capsule())
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, controls ? 96 : 32)
            }
            if let seconds = model.countdown {
                VStack(spacing: 14) {
                    Text(L.nextIn(seconds)).font(Theme.title(20)).foregroundStyle(Theme.text)
                    HStack(spacing: 12) {
                        Button(L.playerNext) {
                            model.cancelCountdown()
                            Task { await model.playNext() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        Button(L.cancel) { model.cancelCountdown() }
                            .buttonStyle(.bordered)
                            .tint(Theme.text)
                    }
                }
                .padding(24)
                .background(Theme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .statusBarHidden(!controls)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AppDelegate.setOrientation(.landscape)
            model.start(store: store)
            scheduleHide()
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            AppDelegate.setOrientation(.all)
        }
        .onChange(of: model.ended) { _, ended in
            if ended { controls = true }
        }
        .onChange(of: holding) { _, on in model.setBoost(on) }
        .alert(L.stillWatchingTitle, isPresented: $model.stillWatching) {
            Button(L.stillWatchingContinue) { model.continueWatching() }
            Button(L.stillWatchingStop, role: .cancel) { dismiss() }
        } message: {
            Text(L.stillWatchingBody)
        }
        .sheet(item: $panel, onDismiss: scheduleHide) { kind in
            TrackPanel(kind: kind, model: model) { panel = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
        }
    }

    private var overlay: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.6), .clear, Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack {
                topBar
                Spacer()
                centerButtons
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold))
            }
            .accessibilityLabel(L.playerClose)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.request.ref.title).font(Theme.title(18)).lineLimit(1)
                if let s = model.request.season, let e = model.request.episode {
                    Text([episodeCode(s, e), model.request.episodeTitle].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer()
            Button { model.setInfoVisible(model.info == nil) } label: {
                Image(systemName: model.info == nil ? "info.circle" : "info.circle.fill").font(.system(size: 20))
            }
            .accessibilityLabel(L.playbackInfo)
            if zoom > 1 {
                Button { withAnimation(.easeOut(duration: 0.2)) { zoom = 1 } } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 20))
                }
                .accessibilityLabel(L.zoomReset)
            }
            audioMenu
            subtitleMenu
            speedMenu
        }
        .foregroundStyle(Theme.text)
    }

    private var audioMenu: some View {
        Button { openPanel(.audio) } label: {
            Image(systemName: "speaker.wave.2").font(.system(size: 20))
        }
        .accessibilityLabel(L.playerAudio)
    }

    private var subtitleMenu: some View {
        Button { openPanel(.subtitles) } label: {
            Image(systemName: "captions.bubble").font(.system(size: 20))
        }
        .accessibilityLabel(L.playerSubtitles)
    }

    private func openPanel(_ kind: PlayerPanel) {
        hideTask?.cancel()
        panel = kind
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { (value: Double) in
                Button { model.setRate(Float(value)); scheduleHide() } label: {
                    let label = value == 1 ? "1×" : String(format: "%.2g×", value)
                    if abs(Double(model.rate) - value) < 0.01 { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 20))
        }
        .accessibilityLabel(L.playerSpeed)
    }

    private var centerButtons: some View {
        HStack(spacing: 56) {
            Button { model.jump(seconds: -10); scheduleHide() } label: {
                Image(systemName: "gobackward.10").font(.system(size: 34))
            }
            Button { model.togglePlay(); scheduleHide() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 48))
            }
            Button { model.jump(seconds: 10); scheduleHide() } label: {
                Image(systemName: "goforward.10").font(.system(size: 34))
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.next != nil && model.request.isEpisode {
                HStack {
                    Spacer()
                    Button {
                        Task { await model.playNext() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.resolvingNext { ProgressView().tint(Theme.onAccent) }
                            Label(L.playerNext, systemImage: "forward.end.fill")
                        }
                        .font(Theme.body(15).weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.onAccent)
                    }
                    .disabled(model.resolvingNext)
                }
            }
            HStack(spacing: 12) {
                Text(clockText(ms: scrubbing ? Int64(scrubValue) : model.timeMs)).font(Theme.mono(12))
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubValue : Double(model.timeMs) },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...Double(max(model.lengthMs, 1)),
                    onEditingChanged: { editing in
                        if editing {
                            scrubValue = Double(model.timeMs)
                            scrubbing = true
                            hideTask?.cancel()
                        } else {
                            model.seek(toMs: Int64(scrubValue))
                            scrubbing = false
                            scheduleHide()
                        }
                    }
                )
                .tint(Theme.accent)
                Text(clockText(ms: model.lengthMs)).font(Theme.mono(12))
            }
            .foregroundStyle(Theme.text)
        }
    }

    /// Dikey kaydırma: sol yarı parlaklık (ekran), sağ yarı ses (VLC, %200'e kadar).
    private func swipe(_ value: DragGesture.Value, size: CGSize) {
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        let isVolume = value.startLocation.x > size.width / 2
        if swipeStart == nil {
            swipeStart = (isVolume ? Double(model.volume) / 200 : Double(UIScreen.main.brightness), isVolume)
        }
        guard let start = swipeStart else { return }
        let delta = -Double(value.translation.height) / Double(max(size.height, 1)) * 1.2
        let next = min(1, max(0, start.value + delta))
        if start.isVolume {
            model.volume = Int32(next * 200)
            swipeIndicator = (next == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", Int(next * 200))
        } else {
            UIScreen.main.brightness = CGFloat(next)
            swipeIndicator = ("sun.max.fill", Int(next * 100))
        }
    }

    /// Duraklatınca sağda oyuncular ve karakterleri.
    private var pausedCast: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(L.cast).font(Theme.title(16)).foregroundStyle(Theme.text)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.cast) { person in
                            HStack(spacing: 10) {
                                RemoteImage(url: TMDBImage.profile(person.profilePath)) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Theme.surfaceHigh
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name).font(Theme.body(13).weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    if let role = person.character, !role.isEmpty {
                                        Text(role).font(Theme.body(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 230)
            .frame(maxHeight: 300)
            .background(Theme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
            .padding(.trailing, 24)
        }
        .allowsHitTesting(true)
    }

    /// Oynatma bilgisi: görüntü, ses, indirme hızı, gösterilen/kaybolan kareler.
    private func infoOverlay(_ info: PlaybackInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.playbackInfo).font(Theme.body(13).weight(.semibold)).foregroundStyle(Theme.accent)
            infoRow(L.infoVideo, [
                info.width.flatMap { w in info.height.map { "\(w)×\($0)" } },
                info.fps.map { L.infoFps($0) },
                info.videoCodec,
            ])
            infoRow(L.infoAudio, [
                info.audioCodec,
                info.audioChannels.map { L.infoChannels($0) },
                info.audioRate.map { L.infoKHz(Double($0) / 1000) },
            ])
            infoRow(L.infoDownload, [info.downloadKbps.map { L.infoMbps(Double($0) / 1000) }])
            infoRow(L.infoFrames, ["\(info.lost) / \(info.displayed)"])
        }
        .padding(12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Theme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private func infoRow(_ label: String, _ parts: [String?]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).frame(width: 110, alignment: .leading)
            Text(parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("—"))
                .font(Theme.mono(11)).foregroundStyle(Theme.text)
        }
    }

    private func toggleControls() {
        model.noteInteraction()
        controls.toggle()
        if controls { scheduleHide() }
    }

    /// Denetimler 4 saniye sonra gizlenir (oynarken).
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && model.playing && !scrubbing && panel == nil { controls = false }
        }
    }
}

enum PlayerPanel: String, Identifiable {
    case audio, subtitles
    var id: String { rawValue }
}

/// Ses ve altyazı seçimi: kaydırılabilir liste; seçince kapanır. Tercih edilen dildekiler önce.
struct TrackPanel: View {
    let kind: PlayerPanel
    @ObservedObject var model: PlayerModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .audio:
                    audioSettings
                    ForEach(model.audioTracks.filter { $0.id >= 0 }) { track in
                        row(track.name, selected: track.id == model.currentAudio) { model.selectAudio(track.id) }
                    }
                case .subtitles:
                    subtitles
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(kind == .audio ? L.playerAudio : L.playerSubtitles)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L.ok, action: close) }
            }
        }
    }

    /// Gece modu ve ses gecikmesi (seçince panel kapanmaz).
    @ViewBuilder
    private var audioSettings: some View {
        Section {
            Toggle(isOn: Binding(get: { model.nightMode }, set: { model.setNightMode($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.nightMode).font(Theme.body(15)).foregroundStyle(Theme.text)
                    Text(L.nightModeDesc).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .listRowBackground(Theme.surfaceHigh)
        }
        Section(L.audioDelay) {
            HStack(spacing: 12) {
                Button { model.setAudioDelay(model.audioDelayMs - 50) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 24))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L.audioEarlier)
                Text(L.audioDelayValue(Double(model.audioDelayMs) / 1000))
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                Button { model.setAudioDelay(model.audioDelayMs + 50) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 24))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L.audioLater)
                if model.audioDelayMs != 0 {
                    Button(L.reset) { model.setAudioDelay(0) }.buttonStyle(.borderless)
                }
            }
            .foregroundStyle(Theme.accent)
            .listRowBackground(Theme.surfaceHigh)
            Text(L.audioDelayHint).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                .listRowBackground(Theme.surfaceHigh)
        }
    }

    @ViewBuilder
    private var subtitles: some View {
        Section(L.subtitleDelay) {
            HStack(spacing: 12) {
                Button { model.setSubtitleDelay(model.subtitleDelayMs - 250) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 24))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L.subtitleEarlier)
                Text(L.subtitleDelayValue(Double(model.subtitleDelayMs) / 1000))
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                Button { model.setSubtitleDelay(model.subtitleDelayMs + 250) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 24))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L.subtitleLater)
                if model.subtitleDelayMs != 0 {
                    Button(L.reset) { model.setSubtitleDelay(0) }.buttonStyle(.borderless)
                }
            }
            .foregroundStyle(Theme.accent)
            .listRowBackground(Theme.surfaceHigh)
        }
        Section {
            row(L.playerSubtitlesOff, selected: model.currentSubtitle < 0) { model.selectSubtitle(-1) }
            ForEach(model.subtitleTracks.filter { $0.id >= 0 }) { track in
                row(track.name, selected: track.id == model.currentSubtitle) { model.selectSubtitle(track.id) }
            }
        }
        if !model.externalSubtitles.isEmpty {
            Section(model.request.url.isFileURL ? L.subtitleDownloaded : L.subtitleSources) {
                ForEach(Array(model.externalSubtitles.enumerated()), id: \.offset) { _, sub in
                    row([sub.lang?.uppercaseTr, sub.id].compactMap { $0 }.joined(separator: " · "), selected: false) {
                        model.selectExternal(sub)
                    }
                }
            }
        }
        Section {
            if let results = model.subtitleResults {
                if results.isEmpty && !model.request.url.isFileURL {
                    Text(L.subtitleNoAddon)
                }
                ForEach(results, id: \.self) { result in
                    Text(result.summary)
                }
            } else {
                Text(L.subtitleSearching)
            }
        }
        .font(Theme.body(12))
        .foregroundStyle(Theme.textSecondary)
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            close()
        } label: {
            HStack {
                Text(title).font(Theme.body(15)).foregroundStyle(Theme.text)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
        }
        .listRowBackground(Theme.surfaceHigh)
    }
}
