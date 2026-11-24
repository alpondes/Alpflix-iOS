import Charts
import SwiftUI

enum StatsPeriod: String, CaseIterable, Identifiable {
    case month, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return L.statsMonth
        case .year: return L.statsYear
        case .all: return L.statsAll
        }
    }

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .month: return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .year: return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .all: return true
        }
    }
}

/// İzleme özeti: saf hesap (izleme kayıtları + yapım bilgisi).
struct StatsSummary {
    struct Bar: Identifiable {
        let label: String
        let hours: Double
        var id: String { label }
    }

    var movies = 0
    var episodes = 0
    var minutes = 0
    var series = 0
    struct GenreShare: Identifiable {
        let name: String
        let minutes: Int
        var id: String { name }
    }

    struct SeriesCount: Identifiable {
        let ref: MediaRef
        let episodes: Int
        var id: String { ref.id }
    }

    var genres: [GenreShare] = []
    var topSeries: [SeriesCount] = []
    var bars: [Bar] = []
    var busiestDay: (Date, Int)?

    @MainActor
    static func make(_ store: LibraryStore, period: StatsPeriod, now: Date = Date()) -> StatsSummary {
        var s = StatsSummary()
        let events = store.data.events.filter { period.contains($0.watchedAt, now: now) }
        var genreMinutes: [String: Int] = [:]
        var seriesEpisodes: [Int: Int] = [:]
        var perDay: [Date: Int] = [:]
        let calendar = Calendar.current
        var perBucket: [Int: Int] = [:]
        for e in events {
            let facts = store.facts("\(e.type.rawValue):\(e.tmdbId)")
            let minutes = facts?.minutes ?? (e.type == .movie ? 105 : 42)
            s.minutes += minutes
            if e.type == .movie { s.movies += 1 } else {
                s.episodes += 1
                seriesEpisodes[e.tmdbId, default: 0] += 1
            }
            for g in facts?.genres ?? [] { genreMinutes[g, default: 0] += minutes }
            perDay[calendar.startOfDay(for: e.watchedAt), default: 0] += minutes
            let bucket = period == .all ? calendar.component(.year, from: e.watchedAt)
                : (period == .year ? calendar.component(.month, from: e.watchedAt) : calendar.component(.day, from: e.watchedAt))
            perBucket[bucket, default: 0] += minutes
        }
        s.series = seriesEpisodes.count
        s.genres = genreMinutes.sorted { $0.value > $1.value }.prefix(6).map { GenreShare(name: $0.key, minutes: $0.value) }
        s.topSeries = seriesEpisodes.sorted { $0.value > $1.value }.prefix(5).compactMap { entry -> SeriesCount? in
            guard let ref = store.data.titles["tv:\(entry.key)"]?.ref, !ref.title.isEmpty else { return nil }
            return SeriesCount(ref: ref, episodes: entry.value)
        }
        if let best = perDay.max(by: { $0.value < $1.value }) { s.busiestDay = (best.key, best.value) }
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "tr_TR")
        let turkishMonths: [String] = monthFormatter.shortStandaloneMonthSymbols
        switch period {
        case .year:
            s.bars = (1...12).map { m in Bar(label: turkishMonths.indices.contains(m - 1) ? turkishMonths[m - 1] : "\(m)", hours: Double(perBucket[m] ?? 0) / 60) }
        case .month:
            let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            s.bars = (1...days).map { d in Bar(label: "\(d)", hours: Double(perBucket[d] ?? 0) / 60) }
        case .all:
            s.bars = perBucket.keys.sorted().map { y in Bar(label: "\(y)", hours: Double(perBucket[y] ?? 0) / 60) }
        }
        return s
    }
}

struct StatsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var period: StatsPeriod = .year
    @State private var filling = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let summary = StatsSummary.make(store, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.tileGap) {
                Picker("", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.gutter)
                if filling {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text(L.statsFilling).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                totals(summary)
                if summary.bars.contains(where: { $0.hours > 0 }) {
                    BentoTile(padding: 18) {
                        TileLabel(text: L.statsHours)
                        Chart(summary.bars) { bar in
                            BarMark(x: .value("", bar.label), y: .value(L.statsHoursAxis, bar.hours))
                                .foregroundStyle(Theme.accent)
                                .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks { _ in AxisValueLabel().font(Theme.mono(9)).foregroundStyle(Theme.textSecondary) }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(Theme.surfaceHigh)
                                AxisValueLabel().font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(height: 180)
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if !summary.genres.isEmpty {
                    BentoTile(padding: 18) {
                        TileLabel(text: L.statsGenres)
                        let maxMinutes = Double(max(1, summary.genres.first?.minutes ?? 1))
                        VStack(spacing: 10) {
                            ForEach(summary.genres) { share in
                                let minutes = share.minutes
                                HStack(spacing: 10) {
                                    Text(share.name).font(Theme.body(14)).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Theme.surfaceHigh)
                                            Capsule()
                                                .fill(Theme.accent)
                                                .frame(width: max(6, geo.size.width * Double(minutes) / maxMinutes))
                                        }
                                    }
                                    .frame(height: 6)
                                    Text(hoursText(minutes)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).frame(width: 64, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if !summary.topSeries.isEmpty {
                    BentoTile(padding: 18) {
                        TileLabel(text: L.statsTopSeries)
                        VStack(spacing: 12) {
                            ForEach(Array(summary.topSeries.enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: item.ref) {
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(Theme.title(26))
                                            .foregroundStyle(index == 0 ? Theme.accent : Theme.textSecondary)
                                            .frame(width: 30)
                                        PosterImage(path: item.ref.posterPath, title: item.ref.title, size: "w185").frame(width: 36)
                                        Text(item.ref.title).font(Theme.body(15)).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer()
                                        Text(L.statsEpisodes(item.episodes)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if let busiest = summary.busiestDay {
                    BentoTile {
                        TileLabel(text: L.dashBusiest)
                        Text(L.statsBusiestDay(SeriesBadges.shortDate(busiest.0), hoursText(busiest.1)))
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if summary.movies + summary.episodes == 0 {
                    MessageView(text: L.statsEmpty)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.stats)
        .task { await fillFacts() }
    }

    /// Büyük toplam süre kutusu (vurgulu) ve üç sayı kutusu; iPad'de tek sıra.
    private func totals(_ s: StatsSummary) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.tileGap), count: sizeClass == .regular ? 4 : 2)
        return LazyVGrid(columns: columns, spacing: Theme.tileGap) {
            tile(hoursText(s.minutes), L.statsTotalTime, accent: true)
            tile("\(s.movies)", L.statsMovies)
            tile("\(s.episodes)", L.statsEpisodesTitle)
            tile("\(s.series)", L.statsSeries)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func tile(_ value: String, _ label: String, accent: Bool = false) -> some View {
        BentoTile(accent: accent) {
            TileLabel(text: label, accent: accent)
            Text(value).font(Theme.mono(30).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func hoursText(_ minutes: Int) -> String {
        minutes >= 60 ? L.statsHoursValue(minutes / 60) : L.statsMinutesValue(minutes)
    }

    /// Süre ve tür bilgisi eksik yapımlar TMDB'den bir kez tamamlanır (en çok 80'er).
    private func fillFacts() async {
        var keys: [(MediaType, Int)] = []
        var seen = Set<String>()
        for e in store.data.events.reversed() {
            let key = "\(e.type.rawValue):\(e.tmdbId)"
            if store.facts(key) == nil, seen.insert(key).inserted { keys.append((e.type, e.tmdbId)) }
        }
        guard !keys.isEmpty else { return }
        filling = true
        defer { filling = false }
        for (type, id) in keys.prefix(80) {
            guard let d = try? await TMDBClient.shared.detail(type, id) else { continue }
            let minutes = type == .movie ? (d.runtime ?? 105) : (d.episodeRunTime?.first ?? d.lastEpisodeToAir?.runtime ?? 42)
            store.setFacts("\(type.rawValue):\(id)", TitleFacts(minutes: max(1, minutes), genres: (d.genres ?? []).map(\.name)))
        }
    }
}
