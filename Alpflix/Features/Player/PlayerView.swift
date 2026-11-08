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
        Menu {
            ForEach(model.audioTracks.filter { $0.id >= 0 }) { track in
                Button { model.selectAudio(track.id); scheduleHide() } label: {
                    if track.id == model.currentAudio { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                }
            }
        } label: {
            Image(systemName: "speaker.wave.2").font(.system(size: 20))
        }
        .accessibilityLabel(L.playerAudio)
    }

    private var subtitleMenu: some View {
        Menu {
            Button { model.selectSubtitle(-1); scheduleHide() } label: {
                if model.currentSubtitle < 0 { Label(L.playerSubtitlesOff, systemImage: "checkmark") } else { Text(L.playerSubtitlesOff) }
            }
            ForEach(model.subtitleTracks.filter { $0.id >= 0 }) { track in
                Button { model.selectSubtitle(track.id); scheduleHide() } label: {
                    if track.id == model.currentSubtitle { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                }
            }
            if !model.externalSubtitles.isEmpty {
                Section {
                    ForEach(Array(model.externalSubtitles.prefix(30).enumerated()), id: \.offset) { _, sub in
                        Button { model.selectExternal(sub); scheduleHide() } label: {
                            Text([sub.lang?.uppercaseTr, sub.id].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble").font(.system(size: 20))
        }
        .accessibilityLabel(L.playerSubtitles)
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
            if !Task.isCancelled && model.playing && !scrubbing { controls = false }
        }
    }
}
