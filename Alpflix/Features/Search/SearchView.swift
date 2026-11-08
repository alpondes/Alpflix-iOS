import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [MediaRef] = []
    @Published var searching = false
    @Published var error: String?

    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            return
        }
        // Yazarken her harfte değil, kısa bir duraksamadan sonra.
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled || text != query.trimmingCharacters(in: .whitespacesAndNewlines) { return }
        searching = true
        defer { searching = false }
        do {
            results = try await TMDBClient.shared.search(text)
            error = nil
        } catch {
            if !Task.isCancelled { self.error = errorText(error) }
        }
    }
}

struct SearchView: View {
    @StateObject private var model = SearchModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.query.trimmingCharacters(in: .whitespaces).count < 2 {
                    MessageView(text: L.searchHint)
                } else if let error = model.error {
                    MessageView(text: error)
                } else if model.results.isEmpty && !model.searching {
                    MessageView(text: L.searchEmpty)
                }
                PosterGrid(items: model.results)
            }
            .padding(.vertical, 12)
        }
        .navigationTitle(L.tabSearch)
        .searchable(text: $model.query, prompt: L.searchPrompt)
        .autocorrectionDisabled()
        .task(id: model.query) { await model.search() }
    }
}
