import SwiftUI

/// Afiş görseli: yüklenirken ve yoksa sakin bir zemin ve ad.
struct PosterImage: View {
    let path: String?
    let title: String
    var size: String = "w342"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.posterRadius).fill(Theme.surfaceHigh)
            RemoteImage(url: TMDBImage.poster(path, size: size)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Text(title)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.posterRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.posterRadius).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

/// Afiş, altında ad ve alt yazı; isteğe bağlı ilerleme çubuğu.
struct PosterCard: View {
    let ref: MediaRef
    var subtitle: String? = nil
    var progress: Double? = nil
    /// nil: bulunduğu yere yayılır (ızgara).
    var width: CGFloat? = Theme.posterWidth
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Satır afişi iPad'de daha geniş.
    private var resolvedWidth: CGFloat? {
        guard let width else { return nil }
        return width == Theme.posterWidth && sizeClass == .regular ? Theme.posterWidthWide : width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                PosterImage(path: ref.posterPath, title: ref.title)
                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.4))
                            Rectangle().fill(Theme.accent).frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(6)
                }
            }
            Text(ref.title)
                .font(Theme.body(14))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: resolvedWidth, alignment: .topLeading)
        .frame(maxWidth: resolvedWidth == nil ? .infinity : nil, alignment: .topLeading)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.title(22))
            .tracking(-0.2)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
    }
}

/// Başlık ve yatay afiş sırası; dokununca yapımın sayfası açılır.
struct MediaRow: View {
    let title: String
    let items: [MediaRef]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { ref in
                            NavigationLink(value: ref) {
                                PosterCard(ref: ref, subtitle: ref.year.map { String($0) })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }
}

/// Afiş ızgarası (keşfet, arama, kütüphane).
struct PosterGrid: View {
    let items: [MediaRef]
    var onAppearLast: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(items) { ref in
                NavigationLink(value: ref) {
                    PosterCard(ref: ref, subtitle: ref.year.map { String($0) }, width: nil)
                }
                .buttonStyle(.plain)
                .onAppear { if ref == items.last { onAppearLast?() } }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

struct MessageView: View {
    let text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button(L.retry, action: retry)
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

func errorText(_ error: Error) -> String {
    if error is TMDBError { return L.errorNoToken }
    return L.errorNetwork
}

/// Geniş görsel: verilen yüksekliğe doldurulur ve kırpılır; doğal genişliği yerleşimi büyütmez
/// (2.1 taşma düzeltmesi: görsel sütunu ekrandan taşırıyordu).
struct BackdropImage: View {
    let url: URL?
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                RemoteImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.surface
                }
            }
            .clipped()
    }
}

/// Ana sayfanın en üstündeki öne çıkan yapım: durum çubuğunun altına uzanan görsel, üstte düğmeler,
/// zemine geçiş, ad ve eylemler. Filmde "İzle" kaynakları, dizide yapım sayfasını açar; "Listem"
/// İzleyeceğim durumunu değiştirir.
struct HeroBanner<TopBar: View>: View {
    let ref: MediaRef
    var topInset: CGFloat = 0
    @ViewBuilder var topBar: () -> TopBar
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let height: CGFloat = (sizeClass == .regular ? 500 : 460) + topInset
        ZStack(alignment: .bottomLeading) {
            BackdropImage(url: TMDBImage.backdrop(ref.backdropPath), height: height)
            LinearGradient(
                stops: [
                    .init(color: Theme.background.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.42),
                    .init(color: Theme.background.opacity(0.8), location: 0.75),
                    .init(color: Theme.background, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 12) {
                Text(ref.title)
                    .font(Theme.title(sizeClass == .regular ? 44 : 34))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text([ref.type == .tv ? L.typeSeries : L.typeMovie, ref.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    if ref.type == .movie {
                        NavigationLink(value: SourcesRoute(ref: ref, imdbId: nil, season: nil, episode: nil)) {
                            heroButton(L.heroWatch, "play.fill", primary: true)
                        }
                    } else {
                        NavigationLink(value: ref) { heroButton(L.heroEpisodes, "play.fill", primary: true) }
                    }
                    let saved = store.status(ref) == .PLAN_TO_WATCH
                    Button {
                        store.setStatus(ref, saved ? nil : .PLAN_TO_WATCH)
                    } label: {
                        heroButton(saved ? L.heroSaved : L.heroSave, saved ? "checkmark" : "plus", primary: false)
                    }
                    NavigationLink(value: ref) {
                        Image(systemName: "info")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 46, height: 46)
                            .glassCapsule()
                    }
                    .accessibilityLabel(ref.type == .tv ? L.seriesDetails : L.movieDetails)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            topBar()
                .padding(.top, topInset + 6)
                .padding(.trailing, Theme.gutter)
        }
    }

    /// Birincil: açık renkli dolu hap; ikincil: cam hap (2.0).
    @ViewBuilder
    private func heroButton(_ title: String, _ icon: String, primary: Bool) -> some View {
        let label = Label(title, systemImage: icon)
            .font(Theme.body(15).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 18)
            .frame(height: 46)
        if primary {
            label
                .background(Theme.text, in: Capsule())
                .foregroundStyle(Theme.background)
        } else {
            label
                .foregroundStyle(Theme.text)
                .glassCapsule()
        }
    }
}
