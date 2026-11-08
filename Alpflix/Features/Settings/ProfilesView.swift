import SwiftUI

/// Profiller: geçiş, ekleme, ad, PIN, silme.
struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var store: LibraryStore
    @State private var newName = ""
    @State private var adding = false
    @State private var renaming: Profile?
    @State private var renameText = ""
    @State private var pinTarget: Profile?
    @State private var pinMode: PinMode = .unlock
    @State private var pinText = ""
    @State private var wrongPin = false

    enum PinMode { case unlock, set, verifyToRemove }

    var body: some View {
        List {
            Section {
                ForEach(profiles.profiles) { p in
                    HStack(spacing: 14) {
                        ProfileAvatar(profile: p, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(Theme.body(16))
                            Text(p.id == profiles.activeId ? L.profileActive : L.profileTapToSwitch)
                                .font(Theme.body(12))
                                .foregroundStyle(p.id == profiles.activeId ? Theme.accent : Theme.textSecondary)
                        }
                        Spacer()
                        if p.locked { Image(systemName: "lock.fill").foregroundStyle(Theme.textSecondary) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(p) }
                    .contextMenu {
                        Button(L.profileRename) { renameText = p.name; renaming = p }
                        if p.locked {
                            Button(L.profilePinRemove) { askPin(p, .verifyToRemove) }
                        } else {
                            Button(L.profilePinSet) { askPin(p, .set) }
                        }
                        if p.id != profiles.activeId && profiles.profiles.count > 1 {
                            Button(L.delete, role: .destructive) { profiles.delete(p.id) }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            } footer: {
                Text(L.profilesHint)
            }
            Section {
                Button(L.profileAdd) { newName = ""; adding = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L.profiles)
        .alert(L.profileAdd, isPresented: $adding) {
            TextField(L.profileName, text: $newName)
            Button(L.ok) { profiles.add(newName) }
            Button(L.cancel, role: .cancel) {}
        }
        .alert(L.profileRename, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L.profileName, text: $renameText)
            Button(L.ok) { if let r = renaming { profiles.rename(r.id, renameText) } }
            Button(L.cancel, role: .cancel) {}
        }
        .alert(pinTitle, isPresented: Binding(get: { pinTarget != nil }, set: { if !$0 { pinTarget = nil } })) {
            SecureField(L.profilePin, text: $pinText).keyboardType(.numberPad)
            Button(L.ok) { submitPin() }
            Button(L.cancel, role: .cancel) {}
        } message: {
            if wrongPin { Text(L.profilePinWrong) }
        }
    }

    private var pinTitle: String {
        switch pinMode {
        case .unlock: return L.profileUnlock(pinTarget?.name ?? "")
        case .set: return L.profilePinNew
        case .verifyToRemove: return L.profilePinCurrent
        }
    }

    private func open(_ p: Profile) {
        guard p.id != profiles.activeId else { return }
        if p.locked { askPin(p, .unlock) } else { profiles.activate(p.id, store: store) }
    }

    private func askPin(_ p: Profile, _ mode: PinMode) {
        pinText = ""
        wrongPin = false
        pinMode = mode
        pinTarget = p
    }

    private func submitPin() {
        guard let p = pinTarget else { return }
        switch pinMode {
        case .set:
            if ProfilePin.valid(pinText) { profiles.setPin(p.id, pinText) }
        case .unlock:
            if ProfilePin.matches(p, pinText) { profiles.activate(p.id, store: store) } else { retry(p) }
        case .verifyToRemove:
            if ProfilePin.matches(p, pinText) { profiles.setPin(p.id, nil) } else { retry(p) }
        }
    }

    private func retry(_ p: Profile) {
        wrongPin = true
        pinText = ""
        DispatchQueue.main.async { pinTarget = p }
    }
}

/// PIN'li profille açılışta kilit ekranı; başka profile de geçilebilir.
struct ProfileGate: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var store: LibraryStore
    @State private var pin = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ProfileAvatar(profile: profiles.active, size: 88)
            Text(profiles.active.name).font(Theme.title(28)).foregroundStyle(Theme.text)
            Text(L.profileGateBody).font(Theme.body(15)).foregroundStyle(Theme.textSecondary)
            SecureField(L.profilePin, text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(Theme.mono(22))
                .padding(12)
                .frame(maxWidth: 200)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 10))
            if wrong { Text(L.profilePinWrong).font(Theme.body(13)).foregroundStyle(.red) }
            Button(L.profileGateOpen) {
                if ProfilePin.matches(profiles.active, pin) { profiles.unlocked = true } else { wrong = true; pin = "" }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!ProfilePin.valid(pin))
            let others = profiles.profiles.filter { $0.id != profiles.activeId && !$0.locked }
            if !others.isEmpty {
                Text(L.profileGateOther).font(Theme.body(14)).foregroundStyle(Theme.textSecondary).padding(.top, 24)
                HStack(spacing: 18) {
                    ForEach(others) { p in
                        Button { profiles.activate(p.id, store: store) } label: {
                            VStack(spacing: 4) {
                                ProfileAvatar(profile: p, size: 52)
                                Text(p.name).font(Theme.body(12)).foregroundStyle(Theme.text)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
