import SwiftUI

/// Alpflix tasarım sistemi (Android ile aynı): koyu zemin, sıcak metin, turuncu vurgu. Saf siyah/beyaz yok.
enum Theme {
    static let background = Color(red: 0x12 / 255, green: 0x10 / 255, blue: 0x14 / 255)
    static let surface = Color(red: 0x1E / 255, green: 0x1A / 255, blue: 0x20 / 255)
    static let surfaceHigh = Color(red: 0x28 / 255, green: 0x23 / 255, blue: 0x2A / 255)
    static let text = Color(red: 0xED / 255, green: 0xE8 / 255, blue: 0xE3 / 255)
    static let textSecondary = Color(red: 0xBD / 255, green: 0xB3 / 255, blue: 0xAD / 255)
    static let accent = Color(red: 0xF2 / 255, green: 0x78 / 255, blue: 0x4B / 255)
    static let onAccent = Color(red: 0x3A / 255, green: 0x12 / 255, blue: 0x06 / 255)

    static let posterRadius: CGFloat = 10
    static let posterWidth: CGFloat = 120
    static let gutter: CGFloat = 16

    /// Başlıklar: Archivo (dar, kalın).
    static func title(_ size: CGFloat) -> Font { .custom("Archivo", size: size).weight(.bold) }
    /// Gövde: Atkinson Hyperlegible Next.
    static func body(_ size: CGFloat = 16) -> Font { .custom("Atkinson Hyperlegible Next", size: size) }
    /// Sayılar: IBM Plex Mono (süreler, S01B05).
    static func mono(_ size: CGFloat = 13) -> Font { .custom("IBM Plex Mono", size: size) }
}

extension String {
    /// Türkçe büyük harf (i → İ).
    var uppercaseTr: String { uppercased(with: Locale(identifier: "tr_TR")) }
}

/// "S01B05" biçimi.
func episodeCode(_ season: Int, _ episode: Int) -> String {
    String(format: "S%02dB%02d", season, episode)
}

/// "1 sa 42 dk" biçimi.
func durationText(minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m) dk" }
    return m == 0 ? "\(h) sa" : "\(h) sa \(m) dk"
}

/// "01:23:45" / "23:45" biçimi.
func clockText(ms: Int64) -> String {
    let total = max(0, Int(ms / 1000))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}
