import SwiftUI

/// Kütüphane: duruma göre yapımlar.
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var status: TitleStatus = .WATCHING

    var body: some View {
        let items = store.titles(with: status).map(\.ref)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                shortcuts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TitleStatus.allCases) { s in
                            Button { status = s } label: {
                                Text(s.label)
                                    .font(Theme.body(14))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(status == s ? Theme.accent : Theme.surfaceHigh, in: Capsule())
                                    .foregroundStyle(status == s ? Theme.onAccent : Theme.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if items.isEmpty {
                    MessageView(text: L.libraryEmpty)
                } else {
                    PosterGrid(items: items)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle(L.tabLibrary)
        .task(id: status) { await fillMissing(items) }
    }

    /// Listeler, takip, takvim, istatistik, indirilenler ve gizlenenler.
    private var shortcuts: some View {
        let items: [(String, String, LibraryRoute)] = [
            (L.lists, "list.bullet", LibraryRoute.lists),
            (L.calendar, "calendar", LibraryRoute.calendar),
            (L.stats, "chart.bar", LibraryRoute.stats),
            (L.followingTitle, "person.2", LibraryRoute.following),
            (L.downloads, "arrow.down.circle", LibraryRoute.downloads),
            (L.hiddenTitle, "eye.slash", LibraryRoute.hidden),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                NavigationLink(value: item.2) {
                    HStack(spacing: 10) {
                        Image(systemName: item.1).foregroundStyle(Theme.accent).frame(width: 22)
                        Text(item.0).font(Theme.body(15)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// Yedekten gelen yapımların afişi yoksa TMDB'den tamamlanır.
    private func fillMissing(_ items: [MediaRef]) async {
        for ref in items where ref.posterPath == nil {
            if let detail = try? await TMDBClient.shared.detail(ref.type, ref.tmdbId) {
                store.updateRef(detail.ref(ref.type))
            }
        }
    }
}
