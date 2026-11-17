import SwiftUI

/// Platforma son gelen yapım (son 90 günde çıkanlar), çıkış tarihiyle.
struct PlatformAddition: Identifiable, Hashable {
    let ref: MediaRef
    let date: Date
    let platform: TMDBProvider

    var id: String { "\(ref.id):\(platform.providerId)" }
}

/// Platformlar sayfasının bölümleri (0.9): her biri ayrı, derli toplu bir liste.
enum PlatformTab: String, CaseIterable, Identifiable {
    case added, upcoming, top10
    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: return L.platformsTabAdded
        case .upcoming: return L.platformsTabUpcoming
        case .top10: return L.platformsTabTop10
        }
    }
}

enum FeedSort: String, CaseIterable, Identifiable {
    case newest, oldest, title
    var id: String { rawValue }

    /// Yakında'da tarih sıraları "en yakın / en uzak", yeni eklenenlerde "yeniden eskiye / eskiden yeniye".
    func label(_ tab: PlatformTab) -> String {
        switch self {
        case .title: return L.sortTitle
        case .newest: return tab == .upcoming ? L.sortLatest : L.sortNewestFirst
        case .oldest: return tab == .upcoming ? L.sortSoonest : L.sortOldest
        }
    }
}

enum FeedType: String, CaseIterable, Identifiable {
    case all, movies, series
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L.all
        case .movies: return L.movies
        case .series: return L.series
        }
    }
}

/// Listedeki satır: tarih, ad, tür, platform; süzme ve sıralama bunlarla.
struct FeedItem<Value: Hashable>: Hashable {
    let date: Date
    let ref: MediaRef
    let platformId: Int?
    let value: Value
}

/// Süzme (platform çoklu seçim, tür), sıralama (Türkçe ad sırası) ve gün başlıkları.
enum PlatformFeed {
    static func apply<V>(_ items: [FeedItem<V>], platforms: Set<Int>, type: FeedType, sort: FeedSort) -> [FeedItem<V>] {
        let visible = items.filter { item in
            let platformOk = platforms.isEmpty || (item.platformId.map { platforms.contains($0) } ?? false)
            let typeOk: Bool
            switch type {
            case .all: typeOk = true
            case .movies: typeOk = item.ref.type == .movie
            case .series: typeOk = item.ref.type == .tv
            }
            return platformOk && typeOk
        }
        let turkish = Locale(identifier: "tr_TR")
        func byTitle(_ a: FeedItem<V>, _ b: FeedItem<V>) -> Bool {
            a.ref.title.compare(b.ref.title, options: [.caseInsensitive, .diacriticInsensitive], locale: turkish) == .orderedAscending
        }
        switch sort {
        case .newest: return visible.sorted { $0.date != $1.date ? $0.date > $1.date : byTitle($0, $1) }
        case .oldest: return visible.sorted { $0.date != $1.date ? $0.date < $1.date : byTitle($0, $1) }
        case .title: return visible.sorted(by: byTitle)
        }
    }

    /// Tarih sıralamasında gün başlıkları (sıra korunur); ada göre sıralamada tek grup (başlıksız).
    static func groups<V>(_ items: [FeedItem<V>], sort: FeedSort) -> [(day: Date?, items: [FeedItem<V>])] {
        guard sort != .title else { return items.isEmpty ? [] : [(nil, items)] }
        var result: [(day: Date?, items: [FeedItem<V>])] = []
        let calendar = Calendar.current
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if let last = result.last, last.day == day {
                result[result.count - 1].items.append(item)
            } else {
                result.append((day, [item]))
            }
        }
        return result
    }
}

@MainActor
final class PlatformsModel: ObservableObject {
    @Published var films: Top10Chart?
    @Published var tv: Top10Chart?
    @Published var matches: [String: MediaRef] = [:]
    @Published var top10Failed = false
    @Published var category: Top10Category = .tv
    @Published var platforms: [TMDBProvider] = []
    /// nil: yükleniyor.
    @Published var additions: [PlatformAddition]?
    @Published var upcoming: [UpcomingEntry]?
    @Published var tab: PlatformTab = .added
    /// Platform süzgeci (boş: hepsi) ve tür; bütün sekmelerde ortak.
    @Published var selected: Set<Int> = []
    @Published var type: FeedType = .all
    @Published var sorts: [PlatformTab: FeedSort] = [.added: .newest, .upcoming: .oldest]
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
        platforms = picked
        selected = selected.filter { id in picked.contains { $0.providerId == id } }
        var found: [PlatformAddition] = []
        for p in picked { found += await TMDBClient.shared.providerRecentEntries(p) }
        additions = found
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

    var netflixSelected: Bool { platforms.contains { $0.providerName.lowercased().contains("netflix") } }

    var tabs: [PlatformTab] { PlatformTab.allCases.filter { $0 != .top10 || netflixSelected } }

    func sort(_ tab: PlatformTab) -> FeedSort { sorts[tab] ?? .newest }

    var filtered: Bool { !selected.isEmpty || type != .all }

    func clearFilter() {
        selected = []
        type = .all
    }

    func toggle(_ id: Int?) {
        guard let id else { selected = []; return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func addedFeed() -> [FeedItem<PlatformAddition>]? {
        additions.map { list in
            PlatformFeed.apply(list.map { FeedItem(date: $0.date, ref: $0.ref, platformId: $0.platform.providerId, value: $0) },
                               platforms: selected, type: type, sort: sort(.added))
        }
    }

    func upcomingFeed() -> [FeedItem<UpcomingEntry>]? {
        upcoming.map { list in
            PlatformFeed.apply(list.map { FeedItem(date: $0.date, ref: $0.ref, platformId: $0.platform?.providerId, value: $0) },
                               platforms: selected, type: type, sort: sort(.upcoming))
        }
    }
}

/// Platformlar (0.9): sekmeler (yeni eklenenler, yakında, Netflix Top 10), ortak süzgeç (platform çoklu
/// seçim, tür) ve sekmeye göre sıralama; satırlar gün başlıklarıyla.
struct PlatformsView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var model = PlatformsModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker(L.platforms, selection: $model.tab) {
                ForEach(model.tabs) { tab in Text(tabTitle(tab)).tag(tab) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            if model.tab != .top10 { filterBar }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    switch model.tab {
                    case .added: addedList
                    case .upcoming: upcomingList
                    case .top10: top10List
                    }
                    Text(L.platformsCredit)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 16)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
            }
            .refreshable { await model.load(force: true) }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.platforms)
        .task { await model.load() }
    }

    private func tabTitle(_ tab: PlatformTab) -> String {
        let count: Int?
        switch tab {
        case .added: count = model.addedFeed()?.count
        case .upcoming: count = model.upcomingFeed()?.count
        case .top10: count = nil
        }
        guard let count, count > 0 else { return tab.label }
        return L.tabCount(tab.label, count)
    }

    // MARK: Süzgeç

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(L.allPlatforms, selected: model.selected.isEmpty, logo: nil) { model.toggle(nil) }
                    ForEach(model.platforms) { p in
                        chip(p.providerName, selected: model.selected.contains(p.providerId), logo: p.logoPath) { model.toggle(p.providerId) }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            HStack(spacing: 8) {
                ForEach(FeedType.allCases) { t in
                    chip(t.label, selected: model.type == t, logo: nil) { model.type = t }
                }
                Spacer(minLength: 4)
                Menu {
                    ForEach(FeedSort.allCases) { option in
                        Button {
                            model.sorts[model.tab] = option
                        } label: {
                            if model.sort(model.tab) == option { Label(option.label(model.tab), systemImage: "checkmark") } else { Text(option.label(model.tab)) }
                        }
                    }
                } label: {
                    Label(model.sort(model.tab).label(model.tab), systemImage: "arrow.up.arrow.down")
                        .font(Theme.body(14))
                        .lineLimit(1)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel(L.sortAccessibility(model.sort(model.tab).label(model.tab)))
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.vertical, 10)
    }

    private func chip(_ title: String, selected: Bool, logo: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let logo {
                    RemoteImage(url: TMDBImage.logo(logo)) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Theme.surfaceHigh
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
                }
                Text(title).font(Theme.body(14)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(selected ? Theme.accent : Theme.surfaceHigh, in: Capsule())
            .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Listeler

    @ViewBuilder
    private var addedList: some View {
        Text(L.addedLegend).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
        if let feed = model.addedFeed() {
            if feed.isEmpty {
                empty(L.noAdditions)
            } else {
                grouped(feed, sort: model.sort(.added)) { item in
                    feedRow(item.ref, platform: item.value.platform, detail: L.releasedOn(shortDate(item.date)))
                }
            }
        } else {
            loading
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        Text(L.upcomingHint).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
        let names = Set(model.platforms.filter { model.selected.contains($0.providerId) }.map(\.providerName))
        let reminders = store.reminders.filter { r in names.isEmpty || r.platform.map { names.contains($0) } == true }
        if !reminders.isEmpty {
            Label(L.reminders, systemImage: "bell.fill").font(Theme.body(15)).foregroundStyle(Theme.accent).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(reminders) { r in
                        NavigationLink(value: r.ref) {
                            PosterCard(ref: r.ref, subtitle: [shortDate(r.date), r.platform].compactMap { $0 }.joined(separator: " · "))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if let feed = model.upcomingFeed() {
            if feed.isEmpty {
                empty(L.upcomingEmpty)
            } else {
                grouped(feed, sort: model.sort(.upcoming)) { item in
                    let entry = item.value
                    let reminded = store.hasReminder(entry.reminder.id)
                    feedRow(entry.ref, platform: entry.platform, detail: "\(entry.kind.label(season: entry.season, episode: entry.episode)) · \(shortDate(entry.date))") {
                        Button {
                            Task { await store.toggleReminder(entry.reminder) }
                        } label: {
                            Image(systemName: reminded ? "bell.fill" : "bell")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(reminded ? Theme.accent : Theme.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(reminded ? L.removeReminder : L.remind)
                    }
                }
            }
        } else {
            loading
        }
    }

    @ViewBuilder
    private var top10List: some View {
        Picker("", selection: $model.category) {
            Text(L.series).tag(Top10Category.tv)
            Text(L.movies).tag(Top10Category.films)
        }
        .pickerStyle(.segmented)
        if let chart = model.chart {
            Text(L.weekEnding(chart.week)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
            ForEach(chart.entries) { entry in rankRow(entry, chart.category) }
        } else if model.top10Failed {
            MessageView(text: L.top10Failed) { Task { await model.load(force: true) } }
        } else {
            loading
        }
    }

    /// Gün başlıkları (ekran okuyucuda başlık) ve satırlar.
    @ViewBuilder
    private func grouped<V: Hashable, Row: View>(_ feed: [FeedItem<V>], sort: FeedSort, @ViewBuilder row: @escaping (FeedItem<V>) -> Row) -> some View {
        let groups = PlatformFeed.groups(feed, sort: sort)
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            if let day = group.day {
                HStack(spacing: 8) {
                    Text(dayLabel(day)).font(Theme.body(16).weight(.semibold)).foregroundStyle(Theme.accent)
                    Text("\(group.items.count)").font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            ForEach(group.items, id: \.self) { item in row(item) }
        }
    }

    /// Satır: afiş, ad, tür ve yıl, platform; altta tarih. Bütün satır tek dokunma hedefi.
    private func feedRow<Trailing: View>(_ ref: MediaRef, platform: TMDBProvider?, detail: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: ref) {
                HStack(spacing: 12) {
                    PosterImage(path: ref.posterPath, title: ref.title)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ref.title).font(Theme.body(15).weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                        Text([ref.type == .tv ? L.typeSeries : L.typeMovie, ref.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 6) {
                            if let platform {
                                RemoteImage(url: TMDBImage.logo(platform.logoPath)) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Theme.surfaceHigh
                                }
                                .frame(width: 18, height: 18)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .accessibilityHidden(true)
                                Text(platform.providerName).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                            } else {
                                Text(L.unknownPlatform).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Text(detail).font(Theme.body(12).weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func rankRow(_ entry: Top10Entry, _ category: Top10Category) -> some View {
        let match = model.matches["\(category.rawValue)|\(entry.row.title)"]
        let row = HStack(spacing: 12) {
            Text("\(entry.row.rank)").font(Theme.mono(28).weight(.semibold)).foregroundStyle(Theme.accent).frame(width: 40)
            PosterImage(path: match?.posterPath, title: entry.row.label).frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(match?.title ?? entry.row.label).font(Theme.body(15).weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                movement(entry)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        if let match {
            NavigationLink(value: match) { row }.buttonStyle(.plain)
        } else {
            row
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

    @ViewBuilder
    private func empty(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.filtered ? L.filterEmpty : text).font(Theme.body(15)).foregroundStyle(Theme.textSecondary)
            if model.filtered {
                Button(L.filterClear) { model.clearFilter() }.foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 16)
    }

    private var loading: some View {
        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding()
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L.dayToday }
        if calendar.isDateInYesterday(day) { return L.dayYesterday }
        if calendar.isDateInTomorrow(day) { return L.dayTomorrow }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM, EEEE"
        return f.string(from: day)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
