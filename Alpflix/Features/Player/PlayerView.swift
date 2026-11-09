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
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?

    init(request: PlayRequest) {
        _model = StateObject(wrappedValue: PlayerModel(request: request))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCVideoView(player: model.player).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
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

    private func toggleControls() {
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

    @ViewBuilder
    private var subtitles: some View {
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
