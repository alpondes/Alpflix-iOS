import SwiftUI

/// Kütüphane: duruma göre yapımlar.
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var status: TitleStatus = .WATCHING

    var body: some View {
        let items = store.titles(with: status).map(\.ref)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: DownloadsRoute()) {
                    Label(L.downloads, systemImage: "arrow.down.circle")
                }
            }
        }
        .task(id: status) { await fillMissing(items) }
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
