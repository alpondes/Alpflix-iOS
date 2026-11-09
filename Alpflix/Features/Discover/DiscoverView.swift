import SwiftUI

@MainActor
final class DiscoverModel: ObservableObject {
    @Published var type: MediaType = .movie
    @Published var genres: [TMDBGenre] = []
    @Published var genre: Int?
    @Published var items: [MediaRef] = []
    @Published var error: String?
    private var page = 0
    private var totalPages = 1
    private var loading = false

    func reload() async {
        page = 0
        totalPages = 1
        items = []
        genres = (try? await TMDBClient.shared.genres(type)) ?? genres
        await more()
    }

    func more() async {
        guard !loading, page < totalPages else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await TMDBClient.shared.discover(type, genre: genre, page: page + 1)
            page += 1
            totalPages = result.totalPages ?? 1
            let new = result.results.compactMap { $0.ref(fallback: type) }
            items += new.filter { n in !items.contains { $0.id == n.id } }
            error = nil
        } catch {
            self.error = errorText(error)
        }
    }
}

/// Keşfet: film/dizi, türe göre popüler yapımlar (sonsuz kaydırma).
struct DiscoverView: View {
    @StateObject private var model = DiscoverModel()
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $model.type) {
                    Text(L.movies).tag(MediaType.movie)
                    Text(L.series).tag(MediaType.tv)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(L.all, selected: model.genre == nil) { model.genre = nil }
                        ForEach(model.genres) { g in
                            chip(g.name, selected: model.genre == g.id) { model.genre = g.id }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if let error = model.error, model.items.isEmpty {
                    MessageView(text: error) { Task { await model.reload() } }
                }
                PosterGrid(items: store.visible(model.items)) { Task { await model.more() } }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle(L.tabDiscover)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: PlatformsRoute()) {
                    Label(L.platforms, systemImage: "tv")
                }
            }
        }
        .task { if model.items.isEmpty { await model.reload() } }
        .onChange(of: model.type) { _, _ in
            model.genre = nil
            Task { await model.reload() }
        }
        .onChange(of: model.genre) { _, _ in Task { await model.reload() } }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Theme.accent : Theme.surfaceHigh, in: Capsule())
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        }
        .buttonStyle(.plain)
    }
}
