import SwiftUI

struct PlatformRow: Identifiable {
    let provider: TMDBProvider
    let items: [MediaRef]

    var id: Int { provider.providerId }
}

@MainActor
final class PlatformsModel: ObservableObject {
    @Published var films: Top10Chart?
    @Published var tv: Top10Chart?
    @Published var matches: [String: MediaRef] = [:]
    @Published var top10Failed = false
    @Published var category: Top10Category = .tv
    @Published var rows: [PlatformRow] = []
    /// nil: yükleniyor.
    @Published var upcoming: [UpcomingEntry]?
    private var loaded = false

    /// Sırayla gösterilen platformlar (Türkiye'de varsa).
    private let wanted = ["netflix", "prime video", "disney", "hbo max", "apple tv", "exxen", "tabii", "gain", "tod"]

    func load(force: Bool = false) async {
        guard force || !loaded else { return }
        loaded = true
        let providers = (try? await TMDBClient.shared.regionProviders()) ?? []
        var picked: [TMDBProvider] = []
        for name in wanted {
            if let p = providers.first(where: { $0.providerName.lowercased().contains(name) }), !picked.contains(p) { picked.append(p) }
        }
        var result: [PlatformRow] = []
        for p in picked {
            if let items = try? await TMDBClient.shared.providerRecent(p.providerId), !items.isEmpty {
                result.append(PlatformRow(provider: p, items: items))
            }
        }
        rows = result
        upcoming = await TMDBClient.shared.upcoming(picked)
        let top = try? await NetflixTop10Store.shared.load(force: force)
        if let t = top {
            films = t.films
            tv = t.tv
            matches = t.matches
            top10Failed = false
        } else {
            top10Failed = films == nil && tv == nil
        }
    }

    var chart: Top10Chart? { category == .films ? films : tv }
}

/// Platformlar: Netflix Türkiye Top 10 (resmî haftalık liste) ve platformlara son gelenler.
struct PlatformsView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var model = PlatformsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                top10
                upcomingSection
                ForEach(model.rows) { row in
                    MediaRow(title: L.platformNew(row.provider.providerName), items: row.items)
                }
                Text(L.platformsCredit)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.vertical, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.platforms)
        .refreshable { await model.load(force: true) }
        .task { await model.load() }
    }

    @ViewBuilder
    private var top10: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L.netflixTop10)
            Picker("", selection: $model.category) {
                Text(L.series).tag(Top10Category.tv)
                Text(L.movies).tag(Top10Category.films)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.gutter)
            if let chart = model.chart {
                Text(L.weekEnding(chart.week)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .bottom, spacing: 14) {
                        ForEach(chart.entries) { entry in
                            rankCard(entry, chart.category)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            } else if model.top10Failed {
                MessageView(text: L.top10Failed) { Task { await model.load(force: true) } }
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding()
            }
        }
    }

    /// Yakında: hatırlatıcılar, sonra dönem başına yatay sıra (bu hafta, gelecek hafta…).
    @ViewBuilder
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: L.upcoming)
            let reminders = store.reminders
            if !reminders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L.reminders, systemImage: "bell.fill").font(Theme.body(15)).foregroundStyle(Theme.accent).padding(.horizontal, Theme.gutter)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(reminders) { r in
                                NavigationLink(value: r.ref) {
                                    PosterCard(ref: r.ref, subtitle: [shortDate(r.date), r.platform].compactMap { $0 }.joined(separator: " · "))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
            }
            if let entries = model.upcoming {
                if entries.isEmpty {
                    MessageView(text: L.upcomingEmpty)
                } else {
                    let groups = Dictionary(grouping: entries) { UpcomingPeriod.of($0.date) }
                    ForEach(UpcomingPeriod.allCases.filter { groups[$0] != nil }, id: \.self) { period in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(period.label).font(Theme.body(15).weight(.semibold)).foregroundStyle(Theme.accent).padding(.horizontal, Theme.gutter)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(groups[period] ?? []) { entry in upcomingCard(entry) }
                                }
                                .padding(.horizontal, Theme.gutter)
                            }
                        }
                    }
                }
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func upcomingCard(_ entry: UpcomingEntry) -> some View {
        let reminded = store.hasReminder(entry.reminder.id)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                NavigationLink(value: entry.ref) {
                    ZStack(alignment: .bottomLeading) {
                        PosterImage(path: entry.ref.posterPath, title: entry.ref.title)
                        Text(shortDate(entry.date))
                            .font(Theme.mono(11).weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Theme.onAccent)
                            .padding(6)
                    }
                }
                .buttonStyle(.plain)
                Button {
                    Task { await store.toggleReminder(entry.reminder) }
                } label: {
                    Image(systemName: reminded ? "bell.fill" : "bell")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(7)
                        .background(reminded ? Theme.accent : Theme.surface.opacity(0.85), in: Circle())
                        .foregroundStyle(reminded ? Theme.onAccent : Theme.text)
                }
                .padding(6)
                .accessibilityLabel(reminded ? L.removeReminder : L.remind)
            }
            Text(entry.ref.title).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(2)
            Text(entry.kind.label(season: entry.season, episode: entry.episode)).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Text(entry.platform?.providerName ?? L.unknownPlatform).font(Theme.body(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .frame(width: 124, alignment: .topLeading)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    @ViewBuilder
    private func rankCard(_ entry: Top10Entry, _ category: Top10Category) -> some View {
        let match = model.matches["\(category.rawValue)|\(entry.row.title)"]
        let card = HStack(alignment: .bottom, spacing: 4) {
            Text("\(entry.row.rank)").font(Theme.mono(40).weight(.semibold)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                PosterImage(path: match?.posterPath, title: entry.row.label)
                    .frame(width: 110)
                Text(match?.title ?? entry.row.label).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(2).frame(width: 110, alignment: .leading)
                movement(entry)
            }
        }
        if let match {
            NavigationLink(value: match) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }

    private func movement(_ entry: Top10Entry) -> some View {
        HStack(spacing: 4) {
            if entry.isNew {
                Text(L.newEntry).foregroundStyle(Theme.accent)
            } else if let m = entry.movement, m > 0 {
                Image(systemName: "arrow.up")
                Text("\(m)")
            } else if let m = entry.movement, m < 0 {
                Image(systemName: "arrow.down")
                Text("\(-m)")
            } else {
                Text(L.sameRank)
            }
            Text("· \(L.weeksCount(entry.row.weeks))")
        }
        .font(Theme.mono(11))
        .foregroundStyle(Theme.textSecondary)
    }
}
