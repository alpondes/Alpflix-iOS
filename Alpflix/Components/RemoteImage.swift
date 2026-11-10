import SwiftUI
import UIKit

/// Bellek önbelleği (disk önbelleği HTTP.session'ın URLCache'i).
enum ImageMemory {
    static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        return cache
    }()
}

/// Uzak görsel: AsyncImage yatay/tembel satırlarda iptal edilen yüklemeyi bir daha denemiyor, görsel boş
/// kalıyordu. Burada görünüm her göründüğünde yükleme yeniden başlar, hata olursa iki kez daha denenir,
/// indirilen görsel bellekte tutulur.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageMemory.cache.object(forKey: $0 as NSURL) })
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = ImageMemory.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        image = nil
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            if let data = try? await HTTP.data(url, timeout: 20), let decoded = UIImage(data: data) {
                ImageMemory.cache.setObject(decoded, forKey: url as NSURL)
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.18)) { image = decoded }
                }
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 600_000_000)
        }
    }
}
