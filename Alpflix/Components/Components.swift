import SwiftUI

/// Afiş görseli: yüklenirken ve yoksa sakin bir zemin ve ad.
struct PosterImage: View {
    let path: String?
    let title: String
    var size: String = "w342"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.posterRadius).fill(Theme.surfaceHigh)
            AsyncImage(url: TMDBImage.poster(path, size: size), transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Text(title)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.posterRadius))
    }
}

/// Afiş, altında ad ve alt yazı; isteğe bağlı ilerleme çubuğu.
struct PosterCard: View {
    let ref: MediaRef
    var subtitle: String? = nil
    var progress: Double? = nil
    /// nil: bulunduğu yere yayılır (ızgara).
    var width: CGFloat? = Theme.posterWidth

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
        .frame(width: width, alignment: .topLeading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .topLeading)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.title(22))
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
                    LazyHStack(alignment: .top, spacing: 12) {
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
