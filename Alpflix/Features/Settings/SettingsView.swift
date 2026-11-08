import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @AppStorage(SettingsKeys.tmdbToken) private var savedToken = ""
    @AppStorage(SettingsKeys.subtitleLanguage) private var subtitleLanguage = "tr"
    @State private var tokenDraft = ""
    @State private var addonUrl = ""
    @State private var adding = false
    @State private var message: String?
    @State private var importing = false

    var body: some View {
        Form {
            Section(L.settingsAddons) {
                ForEach(store.addons) { addon in
                    Toggle(isOn: Binding(get: { addon.enabled }, set: { store.setAddonEnabled(addon, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addon.manifest.name).font(Theme.body(16))
                            Text(addon.maskedUrl).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                }
                .onDelete { offsets in
                    let doomed = offsets.map { store.addons[$0] }
                    doomed.forEach { store.removeAddon($0) }
                }
                .onMove { store.moveAddons(from: $0, to: $1) }
                HStack {
                    TextField(L.settingsAddonUrl, text: $addonUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(L.settingsAddonAdd) { Task { await addAddon() } }
                        .disabled(addonUrl.trimmingCharacters(in: .whitespaces).isEmpty || adding)
                }
            }

            Section {
                SecureField(L.settingsTmdb, text: $tokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(L.settingsTmdbSave) {
                    savedToken = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = L.ok
                }
            } header: {
                Text(L.settingsTmdb)
            } footer: {
                Text(L.settingsTmdbHint)
            }

            Section(L.settingsSubtitleLanguage) {
                Picker(L.settingsSubtitleLanguage, selection: $subtitleLanguage) {
                    Text(L.languageTurkish).tag("tr")
                    Text(L.languageEnglish).tag("en")
                    Text(L.playerSubtitlesOff).tag("none")
                }
            }

            Section {
                Button(L.settingsImport) { importing = true }
            } footer: {
                Text(L.settingsImportHint)
            }

            Section(L.settingsAbout) {
                Text(L.settingsVersion(
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                ))
                Text(L.settingsCredit).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.tabSettings)
        .toolbar { EditButton() }
        .onAppear { tokenDraft = savedToken }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            importBackup(result)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L.ok) { message = nil }
        }
    }

    private func addAddon() async {
        adding = true
        defer { adding = false }
        let url = AddonClient.normalizedManifestUrl(addonUrl)
        do {
            let manifest = try await AddonClient.fetchManifest(url)
            store.addAddon(InstalledAddon(manifestUrl: url, manifest: manifest, enabled: true))
            addonUrl = ""
        } catch {
            message = L.settingsAddonFailed
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let imported = try AndroidBackup.parse(data)
            store.merge(imported)
            message = L.settingsImportDone(imported.titles.count, imported.events.count, imported.addons.count)
        } catch {
            message = L.settingsImportFailed
        }
    }
}
