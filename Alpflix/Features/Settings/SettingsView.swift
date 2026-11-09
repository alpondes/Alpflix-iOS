import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @AppStorage(SettingsKeys.tmdbToken) private var savedToken = ""
    @AppStorage(SettingsKeys.subtitleLanguage) private var subtitleLanguage = "tr"
    @AppStorage(SettingsKeys.autoPlayNext) private var autoPlayNext = true
    @State private var tokenDraft = ""
    @State private var addonUrl = ""
    @State private var adding = false
    @State private var message: String?
    @State private var importing = false
    @State private var exporting = false

    /// Eklentinin sunduğu kaynak türleri ("Kaynak · Altyazı"): altyazı eklentisinin tanınıp tanınmadığı görülsün.
    static func resourceLabels(_ manifest: AddonManifest) -> String {
        manifest.resources.map { resource -> String in
            switch resource.name {
            case "stream": return L.resourceStream
            case "subtitles": return L.resourceSubtitles
            case "catalog": return L.resourceCatalog
            case "meta": return L.resourceMeta
            default: return resource.name
            }
        }
        .joined(separator: " · ")
    }

    var body: some View {
        Form {
            Section {
                NavigationLink { ProfilesView() } label: { Label(L.profiles, systemImage: "person.2") }
            }
            Section(L.settingsAddons) {
                ForEach(store.addons) { addon in
                    Toggle(isOn: Binding(get: { addon.enabled }, set: { store.setAddonEnabled(addon, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addon.manifest.name).font(Theme.body(16))
                            Text(addon.maskedUrl).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                            Text(Self.resourceLabels(addon.manifest)).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
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

            Section(L.settingsPlayer) {
                Picker(L.settingsSubtitleLanguage, selection: $subtitleLanguage) {
                    Text(L.languageTurkish).tag("tr")
                    Text(L.languageEnglish).tag("en")
                    Text(L.playerSubtitlesOff).tag("none")
                }
                Toggle(L.autoPlayNext, isOn: $autoPlayNext).tint(Theme.accent)
            }

            Section {
                Button(L.settingsExport) { exporting = true }
                Button(L.settingsImport) { importing = true }
            } header: {
                Text(L.settingsBackup)
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
        .fileExporter(
            isPresented: $exporting,
            document: BackupDocument(data: store.exportData()),
            contentType: .json,
            defaultFilename: "alpflix-ios-yedek"
        ) { result in
            if case .success = result { message = L.settingsExportDone }
        }
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
            let imported = try LibraryStore.decodeBackup(data)
            store.merge(imported)
            message = L.settingsImportDone(imported.titles.count, imported.events.count, imported.addons.count)
        } catch {
            message = L.settingsImportFailed
        }
    }
}
