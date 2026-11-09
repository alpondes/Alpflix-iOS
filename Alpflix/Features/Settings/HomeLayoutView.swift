import SwiftUI

/// Ayarlar > Ana sayfa düzeni: satırların sırası (sürükle) ve görünürlüğü.
struct HomeLayoutView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var order: [HomeRow] = []
    @State private var hidden: Set<HomeRow> = []

    var body: some View {
        List {
            Section {
                ForEach(order) { row in
                    Toggle(isOn: Binding(
                        get: { !hidden.contains(row) },
                        set: { visible in
                            if visible { hidden.remove(row) } else { hidden.insert(row) }
                            save()
                        }
                    )) {
                        Text(row.label).font(Theme.body(15))
                    }
                    .tint(Theme.accent)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    save()
                }
            } footer: {
                Text(L.homeLayoutHint)
            }
            Section {
                Button(L.homeLayoutReset) {
                    order = HomeRow.allCases
                    hidden = []
                    save()
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.homeLayout)
        .onAppear {
            order = store.homeRows
            hidden = Set(HomeRow.allCases.filter { store.isHomeRowHidden($0) })
        }
    }

    private func save() { store.setHomeLayout(order, hidden: hidden) }
}
