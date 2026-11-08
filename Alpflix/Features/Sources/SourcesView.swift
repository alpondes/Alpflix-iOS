import SwiftUI

/// Oynatıcıya giden istek.
struct PlayRequest: Identifiable, Hashable {
    let ref: MediaRef
    let imdbId: String
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    let url: URL
    let bingeGroup: String?
    let startMs: Int64

    var id: String { "\(ref.id):\(season ?? 0):\(episode ?? 0):\(url.absoluteString.hashValue)" }
    var isEpisode: Bool { season != nil && episode != nil }
}

@MainActor
final class SourcesModel: ObservableObject {
    @Published var items: [StreamCandidate] = []
    @Published var loading = true
    @Published var imdbId: String?
    @Published var error: String?

    func load(_ route: SourcesRoute, addons: [InstalledAddon]) async {
        loading = true
        defer { loading = false }
        var imdb = route.imdbId
        if imdb == nil {
            imdb = try? await TMDBClient.shared.detail(route.ref.type, route.ref.tmdbId).imdb
        }
        imdbId = imdb
        guard let imdb, !imdb.isEmpty else {
            error = L.noImdb
            return
        }
        let id = AddonClient.stremioId(imdb: imdb, season: route.season, episode: route.episode)
        items = await AddonClient.allStreams(addons, type: route.ref.type.addonType, id: id)
    }
}

/// Eklentilerden gelen kaynaklar; hazır (debrid önbelleğinde) ve yüksek çözünürlüklüler önce.
struct SourcesView: View {
    let route: SourcesRoute
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var model = SourcesModel()
    @State private var playing: PlayRequest?

    var body: some View {
        List {
            if model.loading {
                HStack(spacing: 12) {
                    ProgressView().tint(Theme.accent)
                    Text(L.sourcesLoading).font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.background)
            } else if store.addons.isEmpty {
                Text(L.sourcesNoAddons).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            } else if let error = model.error {
                Text(error).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            } else if model.items.isEmpty {
                Text(L.sourcesEmpty).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            }
            ForEach(model.items) { candidate in
                Button {
                    play(candidate)
                } label: {
                    SourceRow(candidate: candidate)
                }
                .disabled(candidate.playableURL == nil)
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(route, addons: store.addons) }
        .fullScreenCover(item: $playing) { request in
            PlayerView(request: request)
                .environmentObject(store)
        }
    }

    private var title: String {
        if let s = route.season, let e = route.episode { return "\(route.ref.title) · \(episodeCode(s, e))" }
        return route.ref.title
    }

    private func play(_ candidate: StreamCandidate) {
        guard let url = candidate.playableURL, let imdb = model.imdbId else { return }
        playing = PlayRequest(
            ref: route.ref,
            imdbId: imdb,
            season: route.season,
            episode: route.episode,
            episodeTitle: route.episodeTitle,
            url: url,
            bingeGroup: candidate.stream.behaviorHints?.bingeGroup,
            startMs: route.startMs
        )
    }
}

struct SourceRow: View {
    let candidate: StreamCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(candidate.info.resolutionLabel)
                    .font(Theme.mono(12).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(candidate.info.resolution >= 1080 ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Theme.onAccent)
                if candidate.info.cached {
                    Text(L.cached).font(Theme.mono(11)).foregroundStyle(Theme.accent)
                }
                ForEach(candidate.info.tags, id: \.self) { tag in
                    Text(tag).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let size = candidate.info.sizeGB {
                    Text(String(format: "%.1f GB", size)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Text(candidate.info.torrentOnly ? L.sourceTorrentOnly : (candidate.stream.title ?? candidate.stream.description ?? candidate.stream.name ?? ""))
                .font(Theme.body(13))
                .foregroundStyle(candidate.playableURL == nil ? Theme.textSecondary : Theme.text)
                .lineLimit(3)
            Text(candidate.addonName).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 6)
    }
}
