import SwiftUI

/// Ayarlar > Wi-Fi eşitleme: eşleştirme kodu, bulunan cihazlar, son eşitleme (Android ile aynı).
struct SyncView: View {
    @ObservedObject private var engine = LanSyncEngine.shared
    @State private var shownCode: String?
    @State private var entering = false
    @State private var input = ""
    @State private var invalid = false
    @State private var confirmUnpair = false

    var body: some View {
        Form {
            Section {
                Text(L.syncIntro).font(Theme.body(14)).foregroundStyle(Theme.text)
            }
            if !engine.paired {
                Section {
                    Button(L.syncCreateCode) { shownCode = engine.createCode() }
                    Button(L.syncEnterCode) {
                        input = ""
                        invalid = false
                        entering = true
                    }
                } footer: {
                    Text(L.syncPairHint)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusText).font(Theme.body(16).weight(.semibold)).foregroundStyle(Theme.text)
                        if let last = engine.lastSync {
                            Text([L.syncLast(relative(last)), engine.lastPeerName].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if let problem = engine.problem {
                            Text(problemText(problem)).font(Theme.body(13)).foregroundStyle(Theme.accent)
                        }
                    }
                }
                if !engine.peers.isEmpty {
                    Section(L.syncDevices) {
                        ForEach(engine.peers) { peer in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name).font(Theme.body(15)).foregroundStyle(Theme.text)
                                Text(peer.lastSync.map { L.syncPeerLast(relative($0)) } ?? L.syncPeerNever)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                Section {
                    Button(L.syncNow) { engine.syncNow() }.disabled(engine.peers.isEmpty)
                    Button(L.syncShowCode) { shownCode = engine.currentCode }
                    Button(L.syncUnpair, role: .destructive) { confirmUnpair = true }
                }
            }
            Section {
                Text(L.syncWhat).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.syncTitle)
        .alert(L.syncCodeTitle, isPresented: Binding(get: { shownCode != nil }, set: { if !$0 { shownCode = nil } })) {
            Button(L.ok, role: .cancel) {}
        } message: {
            Text("\(shownCode ?? "")\n\n\(L.syncCodeHint)")
        }
        .alert(L.syncEnterCode, isPresented: $entering) {
            TextField("XXXX-XXXX-XXXX", text: $input)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button(L.save) {
                if !engine.enterCode(input) { invalid = true }
            }
            Button(L.cancel, role: .cancel) {}
        } message: {
            Text(L.syncCodeFormat)
        }
        .alert(L.syncCodeInvalid, isPresented: $invalid) {
            Button(L.ok, role: .cancel) {}
        }
        .confirmationDialog(L.syncUnpairConfirm, isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button(L.syncUnpair, role: .destructive) { engine.unpair() }
            Button(L.cancel, role: .cancel) {}
        }
    }

    private var statusText: String {
        if !engine.running { return L.syncStatusOff }
        return engine.peers.isEmpty ? L.syncStatusSearching : L.syncStatusConnected
    }

    private func problemText(_ problem: LanSyncEngine.Problem) -> String {
        switch problem {
        case .profileMismatch: return L.syncProblemProfile
        case .locked: return L.syncProblemLocked
        case .connection: return L.syncProblemConnection
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
