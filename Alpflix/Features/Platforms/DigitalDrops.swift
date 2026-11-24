import Foundation

/// Sinemadan dijitale geçiş (Android `domain/platforms/DigitalDrops` ile aynı kural): dijital tarih önce
/// Türkiye'nin, yoksa ABD'nin, yoksa en erken kayıttan; sinema tarihi aynı ülkeden, yoksa TR/ABD'den, yoksa
/// en erkenden. Sinemaya çıkmamış (doğrudan dijital) filmler alınmaz.
struct DigitalWindow: Hashable {
    let theatrical: Date
    let digital: Date
    let country: String
    let note: String?

    var gapDays: Int { Calendar.current.dateComponents([.day], from: theatrical, to: digital).day ?? 0 }
}

struct DigitalDrop: Hashable, Identifiable {
    let ref: MediaRef
    let window: DigitalWindow
    var id: String { ref.id }
}

enum DigitalDrops {
    static let windowDays = 30
    private static let preferred = ["TR", "US"]

    struct Entry {
        let country: String
        let type: Int
        let date: Date
        let note: String?
    }

    static func window(_ entries: [Entry]) -> DigitalWindow? {
        let digital = entries.filter { $0.type == 4 }
        guard let earliest = digital.min(by: { $0.date < $1.date }) else { return nil }
        let chosen = preferred.lazy.compactMap { c in digital.filter { $0.country == c }.min(by: { $0.date < $1.date }) }.first ?? earliest
        let cinema = entries.filter { $0.type == 3 || $0.type == 2 }
        let theatrical = cinema.filter { $0.country == chosen.country }.min(by: { $0.date < $1.date })
            ?? preferred.lazy.compactMap { c in cinema.filter { $0.country == c }.min(by: { $0.date < $1.date }) }.first
            ?? cinema.min(by: { $0.date < $1.date })
        guard let theatrical, theatrical.date < chosen.date else { return nil }
        return DigitalWindow(theatrical: theatrical.date, digital: chosen.date, country: chosen.country,
                             note: chosen.note.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Son 30 günde gelenler (yeniden eskiye) ve önümüzdeki 30 günde gelecekler (yakından uzağa).
    static func split(_ drops: [DigitalDrop], today: Date = Date()) -> (recent: [DigitalDrop], upcoming: [DigitalDrop]) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let from = calendar.date(byAdding: .day, value: -windowDays, to: start) ?? start
        let until = calendar.date(byAdding: .day, value: windowDays + 1, to: start) ?? start
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let recent = drops.filter { $0.window.digital >= from && $0.window.digital < tomorrow }.sorted { $0.window.digital > $1.window.digital }
        let upcoming = drops.filter { $0.window.digital >= tomorrow && $0.window.digital < until }.sorted { $0.window.digital < $1.window.digital }
        return (recent, upcoming)
    }
}
