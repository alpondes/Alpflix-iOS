import SwiftUI

// 2.0 tasarımı (Android 7.0 ile aynı): her şeyi bir arada toplayan pano kutuları, cam inceliği,
// sinematik sadelik. iOS 26'da cam düğmeler sistemin Liquid Glass'ı; önceki sürümlerde ince malzeme.

/// Cam kenarı: üstte parlak, aşağı doğru sönen ince çizgi.
struct GlassBorder: View {
    var radius: CGFloat = Theme.tileRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Theme.text.opacity(0.20), Theme.text.opacity(0.06), Theme.text.opacity(0.03)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
    }
}

/// Pano kutusu: yuvarlak köşe, yükseltilmiş zemin, cam kenarı; [accent] vurgu renginde dolu.
struct BentoTile<Content: View>: View {
    var accent = false
    var padding: CGFloat = 16
    private let content: Content

    init(accent: Bool = false, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent ? Theme.accent : Theme.tile, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .overlay { if !accent { GlassBorder() } }
            .foregroundStyle(accent ? Theme.onAccent : Theme.text)
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
    }
}

/// Kutunun üst etiketi.
struct TileLabel: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text)
            .font(Theme.body(13).weight(.semibold))
            .foregroundStyle(accent ? Theme.onAccent : Theme.textSecondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Görselin üstünde duran cam hap (düğmeler).
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.text.opacity(0.16), lineWidth: 0.75))
        }
    }
}
