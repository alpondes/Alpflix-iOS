import Foundation
import UserNotifications

enum UpcomingKind: String, Codable {
    case newSeries, newSeason, newEpisode, digitalMovie

    func label(season: Int?, episode: Int?) -> String {
        switch self {
        case .newSeries: return L.kindNewSeries
        case .newSeason: return L.kindNewSeason(season ?? 1)
        case .newEpisode: return episodeCode(season ?? 1, episode ?? 1)
        case .digitalMovie: return L.kindDigital
        }
    }
}

struct UpcomingEntry: Identifiable, Hashable {
    let date: Date
    let ref: MediaRef
    let kind: UpcomingKind
    let platform: TMDBProvider?
    let season: Int?
    let episode: Int?

    var id: String { "\(ref.id):\(season ?? 0):\(episode ?? 0):\(platform?.providerId ?? 0)" }

    var reminder: Reminder {
        Reminder(ref: ref, date: date, kind: kind.rawValue, platform: platform?.providerName, season: season, episode: episode)
    }
}

enum UpcomingPeriod: Int, CaseIterable, Comparable {
    case thisWeek, nextWeek, comingWeeks, later

    var label: String {
        switch self {
        case .thisWeek: return L.periodThisWeek
        case .nextWeek: return L.periodNextWeek
        case .comingWeeks: return L.periodComingWeeks
        case .later: return L.periodLater
        }
    }

    static func < (a: UpcomingPeriod, b: UpcomingPeriod) -> Bool { a.rawValue < b.rawValue }

    /// Hafta pazar biter (Türkiye takvimi: pazartesi başlar).
    static func of(_ date: Date, now: Date = Date()) -> UpcomingPeriod {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return .later }
        let endOfWeek = week.end
        if date < endOfWeek { return .thisWeek }
        if date < endOfWeek.addingTimeInterval(7 * 86400) { return .nextWeek }
        if date < endOfWeek.addingTimeInterval(35 * 86400) { return .comingWeeks }
        return .later
    }
}

/// Platform adı → TMDB yayın ağı (platformun kendi yeni dizileri için).
enum PlatformNetworks {
    static func ids(_ name: String) -> [Int] {
        let n = name.lowercased()
        if n.contains("netflix") { return [213] }
        if n.contains("prime video") || n.contains("amazon") { return [1024] }
        if n.contains("disney") { return [2739] }
        if n.contains("apple tv") { return [2552] }
        if n.contains("hbo max") || n == "max" { return [3186] }
        return []
    }

    /// Dijital çıkış notu ("Netflix", "Disney+") bu platformu mu gösteriyor.
    static func noteMatches(_ note: String?, _ platform: String) -> Bool {
        guard let note = note?.lowercased(), !note.isEmpty else { return false }
        let p = platform.lowercased().replacingOccurrences(of: " plus", with: "+")
        let keys = ["netflix", "prime", "disney", "apple", "max", "exxen", "tabii", "gain", "tod"]
        return keys.contains { note.contains($0) && p.contains($0) }
    }
}

/// Yerel bildirimler: çıkış günü saat 10:00.
enum ReminderScheduler {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ reminder: Reminder) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: reminder.date)
        components.hour = 10
        let content = UNMutableNotificationContent()
        content.title = reminder.ref.title
        let kind = UpcomingKind(rawValue: reminder.kind)?.label(season: reminder.season, episode: reminder.episode) ?? ""
        content.body = [L.today(kind), reminder.platform].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    static func cancel(_ reminder: Reminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.id])
    }
}
