import SwiftUI

/// Netflix'te bu haftanın bir numarası; [ref] TMDB eşleşmesi.
struct TopPick: Hashable {
    let title: String
    let ref: MediaRef?
}

/// Ana sayfa panosu (2.0, Android 7.0 ile aynı): bu akşam, bu hafta, dijitale düşenler, bir numara,
/// İzleyeceklerim, bu ay.
@MainActor
final class DashboardModel: ObservableObject {
    @Published var week: [CalendarEntry]?
    @Published var drops: [DigitalDrop]?
    @Published var top: TopPick?

    func loadCalendar(_ store: LibraryStore) async {
        week = await EpisodeCalendar.load(store)
    }

    func loadNetwork() async {
        async let d = TMDBClient.shared.digitalDrops()
        async let t = try? NetflixTop10Store.shared.load()
        drops = await d.recent
        if let result = await t, let first = result.tv?.entries.first {
            top = TopPick(title: first.row.label, ref: result.matches["\(Top10Category.tv.rawValue)|\(first.row.title)"])
        }
    }

    /// Pazartesiden başlayan bu hafta.
    static func weekDays(_ now: Date = Date()) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

struct HomeDashboard: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var model = DashboardModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let calendar = Calendar.current
        let days = DashboardModel.weekDays()
        let entries = model.week ?? []
        let tonight = entries.filter { calendar.isDateInToday($0.date) }
        let perDay = days.map { day in entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.count }
        let planned = store.titles(with: .PLAN_TO_WATCH).count
        let minutes = StatsSummary.make(store, period: .month).minutes

        Group {
            if sizeClass == .regular {
                VStack(spacing: Theme.tileGap) {
                    HStack(spacing: Theme.tileGap) {
                        tonightTile(tonight)
                        dropsTile
                        weekTile(days, perDay).frame(maxWidth: .infinity).layoutPriority(1)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.tileGap) {
                        if let top = model.top { topTile(top).layoutPriority(1) }
                        countTile(L.watchlist, "\(planned)", accent: true)
                        countTile(L.dashMonth, L.dashHours(minutes / 60), accent: false)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: Theme.tileGap) {
                    HStack(spacing: Theme.tileGap) {
                        tonightTile(tonight)
                        dropsTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    weekTile(days, perDay)
                    HStack(spacing: Theme.tileGap) {
                        if let top = model.top { topTile(top) }
                        countTile(L.watchlist, "\(planned)", accent: true)
                        countTile(L.dashMonth, L.dashHours(minutes / 60), accent: false)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .task(id: store.data.titles.count) { await model.loadCalendar(store) }
        .task {
            // Ağ istekleri ana sayfanın kendi satırlarından sonra.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await model.loadNetwork()
        }
    }

    private func tonightTile(_ tonight: [CalendarEntry]) -> some View {
        NavigationLink(value: LibraryRoute.calendar) {
            BentoTile {
                TileLabel(text: L.dashTonight)
                Text(model.week == nil ? "—" : "\(tonight.count)")
                    .font(Theme.mono(40).weight(.semibold))
                    .foregroundStyle(tonight.isEmpty ? Theme.textSecondary : Theme.accent)
                Text(tonight.isEmpty ? L.dashTonightNone : Array(Set(tonight.map(\.ref.title))).sorted().joined(separator: ", "))
                    .font(Theme.body(14))
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }

    private var dropsTile: some View {
        NavigationLink(value: PlatformsRoute(tab: .drops)) {
            BentoTile {
                TileLabel(text: L.dashDrops)
                ZStack(alignment: .leading) {
                    ForEach(Array((model.drops ?? []).prefix(3).enumerated()), id: \.element.id) { index, drop in
                        PosterImage(path: drop.ref.posterPath, title: drop.ref.title, size: "w185")
                            .frame(width: 44)
                            .offset(x: CGFloat(index) * 28)
                    }
                }
                .frame(height: 66, alignment: .leading)
                Text(model.drops.map { L.dashDropsCount($0.count) } ?? "…")
                    .font(Theme.body(14))
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }

    private func weekTile(_ days: [Date], _ perDay: [Int]) -> some View {
        NavigationLink(value: LibraryRoute.calendar) {
            BentoTile {
                HStack {
                    TileLabel(text: L.dashWeek)
                    Spacer()
                    Text(L.calendar).font(Theme.body(13).weight(.semibold)).foregroundStyle(Theme.accent)
                }
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        let today = Calendar.current.isDateInToday(day)
                        VStack(spacing: 6) {
                            Text(Self.weekday(day)).font(Theme.mono(10)).foregroundStyle(today ? Theme.accent : Theme.textSecondary)
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(Theme.mono(15).weight(.medium))
                                .foregroundStyle(today ? Theme.accent : Theme.text)
                            Circle()
                                .fill(perDay[index] == 0 ? Color.clear : (today ? Theme.accent : Theme.text))
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.dashWeek)
    }

    private func topTile(_ top: TopPick) -> some View {
        let content = BentoTile {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    TileLabel(text: L.dashTop)
                    Text(top.ref?.title ?? top.title).font(Theme.title(20)).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let poster = top.ref?.posterPath {
                    PosterImage(path: poster, title: top.title, size: "w185").frame(width: 44)
                }
            }
        }
        return Group {
            if let ref = top.ref {
                NavigationLink(value: ref) { content }.buttonStyle(.plain)
            } else {
                NavigationLink(value: PlatformsRoute(tab: .top10)) { content }.buttonStyle(.plain)
            }
        }
    }

    private func countTile(_ label: String, _ value: String, accent: Bool) -> some View {
        let tile = BentoTile(accent: accent) {
            TileLabel(text: label, accent: accent)
            Spacer(minLength: 4)
            Text(value).font(Theme.mono(26).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        return Group {
            if accent {
                NavigationLink { LibraryView() } label: { tile }.buttonStyle(.plain)
            } else {
                NavigationLink(value: LibraryRoute.stats) { tile }.buttonStyle(.plain)
            }
        }
    }

    private static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f.string(from: date).uppercaseTr
    }
}
