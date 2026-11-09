import SwiftUI
import UserNotifications

/// Takvimdeki tek bölüm.
struct CalendarEntry: Identifiable, Hashable {
    let ref: MediaRef
    let imdbId: String?
    let season: Int
    let episode: Int
    let name: String?
    let date: Date

    var id: String { "\(ref.id):\(season):\(episode)" }
}

/// İzlediğin, izleyeceğin ve bitirdiğin dizilerin son 7 gün ve önümüzdeki 60 gündeki bölümleri.
enum EpisodeCalendar {
    static let statuses: Set<TitleStatus> = [.WATCHING, .PLAN_TO_WATCH, .COMPLETED]

    @MainActor
    static func load(_ store: LibraryStore) async -> [CalendarEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        let from = today.addingTimeInterval(-7 * 86400)
        let until = today.addingTimeInterval(60 * 86400)
        let series = store.data.titles.values.filter { $0.ref.type == .tv && $0.status.map(statuses.contains) == true }
        var entries: [CalendarEntry] = []
        for title in series {
            guard let d = try? await TMDBClient.shared.detail(.tv, title.ref.tmdbId) else { continue }
            let ref = d.ref(.tv)
            var seasons = Set<Int>()
            if let next = d.nextEpisodeToAir, let date = dateOf(next.airDate), date <= until { seasons.insert(next.seasonNumber) }
            if let last = d.lastEpisodeToAir, let date = dateOf(last.airDate), date >= from { seasons.insert(last.seasonNumber) }
            for number in seasons {
                guard let season = try? await TMDBClient.shared.season(ref.tmdbId, number) else { continue }
                for e in season.episodes {
                    guard let date = dateOf(e.airDate), date >= from, date <= until else { continue }
                    entries.append(CalendarEntry(ref: ref, imdbId: d.imdb ?? title.imdbId, season: e.seasonNumber,
                                                 episode: e.episodeNumber, name: e.name, date: date))
                }
            }
        }
        return entries.sorted { $0.date != $1.date ? $0.date < $1.date : $0.ref.title < $1.ref.title }
    }
}

/// Yeni bölüm bildirimleri: çıkış günü saat 10'da (en çok 40 bildirim; iOS sınırı 64).
enum EpisodeAlerts {
    private static let prefix = "ep:"
    private static let lastRefreshKey = "episode_alerts_refreshed"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: SettingsKeys.episodeAlerts) }

    static func schedule(_ entries: [CalendarEntry]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }
        let today = Calendar.current.startOfDay(for: Date())
        for entry in entries.filter({ $0.date >= today }).prefix(40) {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: entry.date)
            components.hour = 10
            let content = UNMutableNotificationContent()
            content.title = entry.ref.title
            content.body = L.episodeAlert(episodeCode(entry.season, entry.episode), entry.name)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + entry.id, content: content, trigger: trigger))
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
    }

    /// Ana sayfadan günde bir: açıksa bildirimler yenilenir.
    @MainActor
    static func refreshIfNeeded(_ store: LibraryStore) async {
        guard enabled else { return }
        let last = UserDefaults.standard.double(forKey: lastRefreshKey)
        guard Date().timeIntervalSince1970 - last > 12 * 3600 else { return }
        await schedule(await EpisodeCalendar.load(store))
    }
}

struct CalendarView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var entries: [CalendarEntry]?
    @AppStorage(SettingsKeys.episodeAlerts) private var alerts = false

    var body: some View {
        List {
            Section {
                Toggle(L.episodeAlertsToggle, isOn: $alerts)
                    .tint(Theme.accent)
                    .listRowBackground(Theme.surface)
            } footer: {
                Text(L.episodeAlertsHint)
            }
            if let entries {
                if entries.isEmpty {
                    Text(L.calendarEmpty).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
                }
                ForEach(groups(entries), id: \.day) { group in
                    Section(dayTitle(group.day)) {
                        ForEach(group.items) { entry in
                            NavigationLink(value: entry.ref) { row(entry) }
                                .listRowBackground(Theme.background)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Text(L.calendarLoading).font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.calendar)
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: alerts) { _, on in
            Task {
                if on { _ = await ReminderScheduler.requestPermission() }
                await EpisodeAlerts.schedule(entries ?? [])
            }
        }
    }

    private func reload() async {
        let loaded = await EpisodeCalendar.load(store)
        entries = loaded
        await EpisodeAlerts.schedule(loaded)
    }

    private struct DayGroup {
        let day: Date
        let items: [CalendarEntry]
    }

    private func groups(_ entries: [CalendarEntry]) -> [DayGroup] {
        let grouped = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { DayGroup(day: $0, items: grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L.dayToday }
        if calendar.isDateInTomorrow(day) { return L.dayTomorrow }
        if calendar.isDateInYesterday(day) { return L.dayYesterday }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f.string(from: day)
    }

    private func row(_ entry: CalendarEntry) -> some View {
        let watched = store.watchedEpisodes(entry.ref.tmdbId).contains(EpisodeRef(season: entry.season, episode: entry.episode))
        return HStack(spacing: 12) {
            PosterImage(path: entry.ref.posterPath, title: entry.ref.title, size: "w154")
                .frame(width: 44, height: 66)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.ref.title).font(Theme.body(15).weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text([episodeCode(entry.season, entry.episode), entry.name].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.mono(12))
                    .foregroundStyle(watched ? Theme.textSecondary : Theme.accent)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if watched {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityLabel(L.watched)
            }
        }
    }
}
