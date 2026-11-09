import SwiftUI

/// Kütüphane > Listeler: kendi listeleri ve akıllı listeler.
struct ListsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var editing: ListEditorTarget?

    var body: some View {
        List {
            if store.lists.isEmpty {
                Text(L.listsEmpty).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            }
            ForEach(store.lists) { list in
                NavigationLink(value: LibraryRoute.list(list.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: list.isSmart ? "sparkles" : "list.bullet")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name).font(Theme.body(16)).foregroundStyle(Theme.text)
                            Text(list.isSmart ? L.listSmart : L.listCount(list.items.count))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.background)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.deleteList(list.id) } label: { Label(L.delete, systemImage: "trash") }
                }
            }
            .onMove { store.moveLists(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.lists)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = ListEditorTarget(listId: nil, smart: false) } label: { Label(L.listNew, systemImage: "list.bullet") }
                    Button { editing = ListEditorTarget(listId: nil, smart: true) } label: { Label(L.listNewSmart, systemImage: "sparkles") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L.listNew)
            }
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        .sheet(item: $editing) { target in
            ListEditorView(target: target).environmentObject(store)
        }
    }
}

struct ListEditorTarget: Identifiable {
    let listId: UUID?
    let smart: Bool
    var id: String { "\(listId?.uuidString ?? "new")-\(smart)" }
}

@MainActor
final class SmartListModel: ObservableObject {
    @Published var items: [MediaRef] = []
    @Published var loading = false
    @Published var error: String?
    private var page = 0
    private var totalPages = 1
    private var rule: SmartRule?

    func reset(_ rule: SmartRule) async {
        self.rule = rule
        page = 0
        totalPages = 1
        items = []
        await more(nil)
    }

    func more(_ store: LibraryStore?) async {
        guard let rule, !loading, page < totalPages else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await TMDBClient.shared.smart(rule, page: page + 1)
            page += 1
            totalPages = min(result.totalPages ?? 1, 20)
            let new = result.results.compactMap { $0.ref(fallback: rule.type) }
            items += new.filter { n in !items.contains { $0.id == n.id } }
            error = nil
        } catch {
            self.error = errorText(error)
        }
    }
}

/// Bir liste: elle listede öğeler (basılı tutunca çıkar), akıllı listede kurala uyan TMDB yapımları.
struct ListDetailView: View {
    let listId: UUID
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var smart = SmartListModel()
    @State private var editing: ListEditorTarget?

    private var list: UserList? { store.lists.first { $0.id == listId } }

    var body: some View {
        ScrollView {
            if let list {
                if let rule = list.rule {
                    let shown = store.visible(smart.items).filter { !rule.hideKnown || !store.isKnown($0) }
                    if let error = smart.error, shown.isEmpty {
                        MessageView(text: error) { Task { await smart.reset(rule) } }
                    } else if shown.isEmpty && !smart.loading {
                        MessageView(text: L.listSmartEmpty)
                    }
                    PosterGrid(items: shown) { Task { await smart.more(store) } }
                        .padding(.vertical, 12)
                } else if list.items.isEmpty {
                    MessageView(text: L.listManualEmpty)
                } else {
                    manualGrid(list)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(list?.name ?? L.lists)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = ListEditorTarget(listId: listId, smart: list?.isSmart ?? false) } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(L.listEdit)
            }
        }
        .sheet(item: $editing) { target in
            ListEditorView(target: target).environmentObject(store)
        }
        .task(id: list?.rule) {
            if let rule = list?.rule { await smart.reset(rule) }
        }
    }

    private func manualGrid(_ list: UserList) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12, alignment: .top)], alignment: .leading, spacing: 18) {
            ForEach(list.items, id: \.ref.id) { entry in
                NavigationLink(value: entry.ref) {
                    PosterCard(ref: entry.ref, subtitle: entry.ref.year.map { String($0) }, width: nil)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { store.toggleInList(list.id, entry.ref) } label: {
                        Label(L.listRemoveItem, systemImage: "minus.circle")
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
    }
}

/// Liste oluşturma/düzenleme; akıllı listede kural alanları.
struct ListEditorView: View {
    let target: ListEditorTarget
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rule = SmartRule()
    @State private var genres: [TMDBGenre] = []
    @State private var yearFrom = ""
    @State private var yearTo = ""
    @State private var useVote = false
    @State private var minVote = 7.0

    private let languages: [(String, String)] = [
        ("", L.languageAny), ("tr", L.languageTurkish), ("en", L.languageEnglish), ("ko", L.languageKorean),
        ("ja", L.languageJapanese), ("es", L.languageSpanish), ("fr", L.languageFrench), ("de", L.languageGerman),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(L.listName) {
                    TextField(L.listName, text: $name)
                }
                if target.smart {
                    Section(L.listRule) {
                        Picker(L.listType, selection: $rule.type) {
                            Text(L.movies).tag(MediaType.movie)
                            Text(L.series).tag(MediaType.tv)
                        }
                        Picker(L.listSort, selection: $rule.sort) {
                            ForEach(SmartSort.allCases) { Text($0.label).tag($0) }
                        }
                        Picker(L.listLanguage, selection: Binding(get: { rule.language ?? "" }, set: { rule.language = $0.isEmpty ? nil : $0 })) {
                            ForEach(languages.indices, id: \.self) { i in Text(languages[i].1).tag(languages[i].0) }
                        }
                        HStack {
                            TextField(L.listYearFrom, text: $yearFrom).keyboardType(.numberPad)
                            Text("–").foregroundStyle(Theme.textSecondary)
                            TextField(L.listYearTo, text: $yearTo).keyboardType(.numberPad)
                        }
                        Toggle(L.listMinVoteToggle, isOn: $useVote).tint(Theme.accent)
                        if useVote {
                            Stepper(value: $minVote, in: 1...9.5, step: 0.5) {
                                Text(L.listMinVote(minVote)).font(Theme.mono(14))
                            }
                        }
                        Toggle(L.listHideKnown, isOn: $rule.hideKnown).tint(Theme.accent)
                    }
                    Section(L.genres) {
                        ForEach(genres) { genre in
                            Button {
                                if let i = rule.genres.firstIndex(of: genre.id) { rule.genres.remove(at: i) } else { rule.genres.append(genre.id) }
                            } label: {
                                HStack {
                                    Text(genre.name).foregroundStyle(Theme.text)
                                    Spacer()
                                    if rule.genres.contains(genre.id) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(target.listId == nil ? (target.smart ? L.listNewSmart : L.listNew) : L.listEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: fill)
            .task(id: rule.type) {
                genres = (try? await TMDBClient.shared.genres(rule.type)) ?? []
                rule.genres = rule.genres.filter { id in genres.isEmpty || genres.contains { $0.id == id } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fill() {
        guard let id = target.listId, let list = store.lists.first(where: { $0.id == id }) else { return }
        name = list.name
        if let r = list.rule {
            rule = r
            yearFrom = r.yearFrom.map(String.init) ?? ""
            yearTo = r.yearTo.map(String.init) ?? ""
            useVote = r.minVote != nil
            minVote = r.minVote ?? 7
        }
    }

    private func save() {
        var finalRule: SmartRule?
        if target.smart {
            rule.yearFrom = Int(yearFrom)
            rule.yearTo = Int(yearTo)
            rule.minVote = useVote ? minVote : nil
            finalRule = rule
        }
        if let id = target.listId {
            store.updateList(id, name: name, rule: finalRule)
        } else {
            store.createList(name: name, rule: finalRule)
        }
        dismiss()
    }
}

/// Yapım sayfasındaki "Listeye ekle" menüsü: elle listeler işaretli; yeni liste oluşturulabilir.
struct AddToListMenu: View {
    let ref: MediaRef
    @EnvironmentObject private var store: LibraryStore
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        Menu {
            ForEach(store.lists.filter { !$0.isSmart }) { list in
                Button { store.toggleInList(list.id, ref) } label: {
                    if store.isInList(list.id, ref) { Label(list.name, systemImage: "checkmark") } else { Text(list.name) }
                }
            }
            Button { creating = true } label: { Label(L.listNew, systemImage: "plus") }
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 20))
                .foregroundStyle(Theme.text)
                .padding(8)
        }
        .accessibilityLabel(L.listAdd)
        .alert(L.listNew, isPresented: $creating) {
            TextField(L.listName, text: $newName)
            Button(L.save) {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let id = store.createList(name: name, rule: nil)
                    store.toggleInList(id, ref)
                }
                newName = ""
            }
            Button(L.cancel, role: .cancel) { newName = "" }
        }
    }
}
