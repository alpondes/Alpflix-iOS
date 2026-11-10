import SwiftUI

/// Kişi sayfası: kısa bilgi, takip, filmografi (izlenenler işaretli) ve tamamlama oranı.
struct PersonView: View {
    let personId: Int
    @EnvironmentObject private var store: LibraryStore
    @State private var person: TMDBPerson?
    @State private var error: String?
    @State private var showBio = false

    var body: some View {
        ScrollView {
            if let person {
                content(person)
            } else if let error {
                MessageView(text: error) { Task { await load() } }.padding(.top, 80)
            } else {
                ProgressView().tint(Theme.accent).padding(.top, 120).frame(maxWidth: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(person?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { if person == nil { await load() } }
    }

    private func load() async {
        do {
            person = try await TMDBClient.shared.person(personId)
            error = nil
        } catch {
            self.error = errorText(error)
        }
    }

    /// Oyunculuk ve yönetmenlik; aynı yapım bir kez, yeniden eskiye.
    private func works(_ p: TMDBPerson) -> [TMDBPersonCredit] {
        let crew = (p.combinedCredits?.crew ?? []).filter { ["Director", "Screenplay", "Writer", "Creator"].contains($0.job ?? "") }
        let all = (p.knownForDepartment == "Acting" ? (p.combinedCredits?.cast ?? []) + crew : crew + (p.combinedCredits?.cast ?? []))
        var seen = Set<String>()
        return all.filter { credit in
            guard let ref = credit.ref, credit.posterPath != nil else { return false }
            // Talk show ve haber programlarındaki konuk çıkışları filmografiyi doldurmasın.
            if ref.type == .tv, (credit.episodeCount ?? 0) <= 1, credit.character?.lowercased().contains("self") == true { return false }
            return seen.insert(ref.id).inserted
        }
        .sorted { ($0.date ?? "9999") > ($1.date ?? "9999") }
    }

    private func isWatched(_ ref: MediaRef) -> Bool {
        ref.type == .movie ? store.isMovieWatched(ref.tmdbId) : !store.watchedEpisodes(ref.tmdbId).isEmpty
    }

    @ViewBuilder
    private func content(_ p: TMDBPerson) -> some View {
        let list = works(p)
        let released = list.filter { credit in dateOf(credit.date).map { $0 <= Date() } ?? false }
        let watched = released.filter { credit in credit.ref.map(isWatched) ?? false }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(url: TMDBImage.profile(p.profilePath)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.surfaceHigh
                }
                .frame(width: 110, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: Theme.posterRadius))
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.name).font(Theme.title(24)).foregroundStyle(Theme.text)
                    if let line = lifeLine(p) {
                        Text(line).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                    }
                    if !released.isEmpty {
                        Text(L.filmographyProgress(watched, released.count))
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.accent)
                    }
                    let following = store.isFollowing(p.id)
                    Button {
                        store.toggleFollow(FollowedPerson(id: p.id, name: p.name, profilePath: p.profilePath,
                                                          department: p.knownForDepartment, followedAt: Date()))
                    } label: {
                        Label(following ? L.following : L.follow, systemImage: following ? "checkmark" : "plus")
                            .font(Theme.body(14).weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(following ? Theme.surfaceHigh : Theme.accent, in: Capsule())
                            .foregroundStyle(following ? Theme.text : Theme.onAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
            if let bio = p.biography, !bio.isEmpty {
                Text(bio)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.text)
                    .lineLimit(showBio ? nil : 5)
                    .onTapGesture { showBio.toggle() }
                    .padding(.horizontal, Theme.gutter)
            }
            SectionTitle(text: L.filmography)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 12, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(list, id: \.self) { credit in
                    if let ref = credit.ref {
                        NavigationLink(value: ref) {
                            ZStack(alignment: .topTrailing) {
                                PosterCard(ref: ref, subtitle: [ref.year.map { String($0) }, credit.character ?? credit.job]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), width: nil)
                                if isWatched(ref) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Theme.accent)
                                        .background(Circle().fill(Theme.background))
                                        .padding(6)
                                        .accessibilityLabel(L.watched)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.vertical, 16)
    }

    private func lifeLine(_ p: TMDBPerson) -> String? {
        var parts: [String] = []
        if let born = dateOf(p.birthday) {
            let end = dateOf(p.deathday) ?? Date()
            let age = Calendar.current.dateComponents([.year], from: born, to: end).year ?? 0
            parts.append(p.deathday == nil ? L.personAge(yearOf(p.birthday) ?? 0, age) : L.personLived(yearOf(p.birthday) ?? 0, yearOf(p.deathday) ?? 0))
        }
        if let place = p.placeOfBirth, !place.isEmpty { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Kütüphane > Takip ettiklerim.
struct FollowingView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        List {
            if store.following.isEmpty {
                Text(L.followingEmpty).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            }
            ForEach(store.following) { person in
                NavigationLink(value: PersonRoute(id: person.id)) {
                    HStack(spacing: 12) {
                        RemoteImage(url: TMDBImage.profile(person.profilePath)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Theme.surfaceHigh
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(Theme.body(16)).foregroundStyle(Theme.text)
                            if let department = person.department {
                                Text(department == "Acting" ? L.departmentActing : (department == "Directing" ? L.departmentDirecting : department))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.background)
                .swipeActions {
                    Button(role: .destructive) { store.toggleFollow(person) } label: { Label(L.unfollow, systemImage: "person.badge.minus") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.followingTitle)
    }
}

/// Kütüphane > Gizlenenler ("İlgilenmiyorum" denenler).
struct HiddenTitlesView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        List {
            if store.hiddenTitles.isEmpty {
                Text(L.hiddenEmpty).font(Theme.body(15)).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            }
            ForEach(store.hiddenTitles) { ref in
                NavigationLink(value: ref) {
                    Text([ref.title, ref.year.map { String($0) }].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.text)
                }
                .listRowBackground(Theme.background)
                .swipeActions {
                    Button { store.setHidden(ref, false) } label: { Label(L.unhide, systemImage: "eye") }.tint(Theme.accent)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.hiddenTitle)
    }
}
