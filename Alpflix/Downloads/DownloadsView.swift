import SwiftUI

/// Kütüphane > İndirilenler: ilerleme, duraklat/sürdür, oynat, sil; kullanılan ve boş alan.
struct DownloadsView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var downloads = DownloadStore.shared
    @State private var playing: PlayRequest?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(downloads.wifi ? L.downloadWifiOnly : L.downloadWaitingWifi)
                        .font(Theme.body(14))
                        .foregroundStyle(downloads.wifi ? Theme.textSecondary : Theme.accent)
                    Text(L.downloadSpace(Self.bytes(downloads.usedBytes), Self.bytes(downloads.freeBytes)))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.background)
            }
            if downloads.items.isEmpty {
                Text(L.downloadsEmpty)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.background)
            }
            ForEach(downloads.items) { item in
                DownloadRow(item: item, wifi: downloads.wifi) { play(item) }
                    .listRowBackground(Theme.background)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { downloads.delete(item) } label: { Label(L.delete, systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.downloads)
        .fullScreenCover(item: $playing) { request in
            PlayerView(request: request).environmentObject(store)
        }
    }

    private func play(_ item: DownloadItem) {
        let start = store.progress(item.ref, season: item.season, episode: item.episode)?.positionMs ?? 0
        playing = downloads.playRequest(item, startMs: start)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let wifi: Bool
    let onPlay: () -> Void
    @ObservedObject private var downloads = DownloadStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(path: item.ref.posterPath, title: item.ref.title)
                .frame(width: 54, height: 81)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.ref.title).font(Theme.body(16).weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                if let s = item.season, let e = item.episode {
                    Text([episodeCode(s, e), item.episodeTitle].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
                switch item.state {
                case .running:
                    ProgressView(value: item.fraction).tint(Theme.accent)
                    Text(wifi ? L.downloadProgress(DownloadsView.bytes(item.written), DownloadsView.bytes(item.total)) : L.downloadWaitingWifi)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                case .paused:
                    ProgressView(value: item.fraction).tint(Theme.textSecondary)
                    Text(L.downloadPaused).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                case .done:
                    Text("\(L.downloadDone) · \(DownloadsView.bytes(item.total))").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                case .failed:
                    Text(item.problem ?? L.downloadFailed).font(Theme.body(12)).foregroundStyle(Theme.accent)
                }
                actions
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch item.state {
            case .done:
                button(L.downloadPlay, "play.fill", action: onPlay)
            case .running:
                button(L.downloadPause, "pause.fill") { downloads.pause(item) }
            case .paused:
                button(L.downloadResume, "arrow.down") { downloads.resume(item) }
            case .failed:
                button(L.downloadRetry, "arrow.clockwise") { downloads.resume(item) }
            }
        }
    }

    private func button(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.body(13).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.surfaceHigh, in: Capsule())
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.borderless)
    }
}
