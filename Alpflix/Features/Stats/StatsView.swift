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

    var body: some View {
        let summary = StatsSummary.make(store, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
                    SectionTitle(text: L.statsHours)
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
                    .padding(.horizontal, Theme.gutter)
                }
                if !summary.genres.isEmpty {
                    SectionTitle(text: L.statsGenres)
                    let maxMinutes = Double(max(1, summary.genres.first?.minutes ?? 1))
                    VStack(spacing: 8) {
                        ForEach(summary.genres) { share in
                            let minutes = share.minutes
                            HStack(spacing: 10) {
                                Text(share.name).font(Theme.body(14)).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.accent)
                                        .frame(width: max(4, geo.size.width * Double(minutes) / maxMinutes))
                                }
                                .frame(height: 10)
                                Text(hoursText(minutes)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if !summary.topSeries.isEmpty {
                    SectionTitle(text: L.statsTopSeries)
                    VStack(spacing: 10) {
                        ForEach(summary.topSeries) { item in
                            NavigationLink(value: item.ref) {
                                HStack {
                                    Text(item.ref.title).font(Theme.body(15)).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                    Text(L.statsEpisodes(item.episodes)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                if let busiest = summary.busiestDay {
                    Text(L.statsBusiestDay(SeriesBadges.shortDate(busiest.0), hoursText(busiest.1)))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
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

    private func totals(_ s: StatsSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile(hoursText(s.minutes), L.statsTotalTime)
            tile("\(s.movies)", L.statsMovies)
            tile("\(s.episodes)", L.statsEpisodesTitle)
            tile("\(s.series)", L.statsSeries)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.mono(24).weight(.semibold)).foregroundStyle(Theme.text)
            Text(label).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
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
