import CryptoKit
import Foundation
import SwiftUI

/// Profil: her profilin ayrı veri dosyası var (kütüphane, geçmiş, eklentiler). İlk profil "Alp" eski dosyayı kullanır.
struct Profile: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    var color: Int
    var pinHash: String?
    var pinSalt: String?

    var locked: Bool { pinHash != nil }

    var fileName: String { id == 0 ? "alpflix.json" : "alpflix_p\(id).json" }
}

enum ProfileColors {
    static let all: [Color] = [
        Theme.accent,
        Color(red: 0x9C / 255, green: 0xCF / 255, blue: 0xC4 / 255),
        Color(red: 0xE3 / 255, green: 0xB6 / 255, blue: 0x5C / 255),
        Color(red: 0xC9 / 255, green: 0x8B / 255, blue: 0x7A / 255),
        Color(red: 0x8D / 255, green: 0xB5 / 255, blue: 0x80 / 255),
        Color(red: 0xD9 / 255, green: 0xC2 / 255, blue: 0xB5 / 255),
    ]
}

enum ProfilePin {
    static func valid(_ pin: String) -> Bool { pin.count == 4 && pin.allSatisfy(\.isNumber) }

    static func hash(_ pin: String, salt: String) -> String {
        SHA256.hash(data: Data("\(salt):\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func newSalt() -> String { UUID().uuidString }

    static func matches(_ profile: Profile, _ pin: String) -> Bool {
        guard let hash = profile.pinHash, let salt = profile.pinSalt else { return true }
        return self.hash(pin, salt: salt) == hash
    }
}

/// Profil listesi ve etkin profil (UserDefaults; profil verisine dahil değil).
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile]
    @Published private(set) var activeId: Int
    /// Bu açılışta etkin profilin kilidi açıldı mı (PIN'siz profil hep açık).
    @Published var unlocked: Bool

    private let key = "profiles_v1"
    private let activeKey = "profile_active"

    init() {
        let stored = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
        let list = (stored?.isEmpty == false) ? stored! : [Profile(id: 0, name: L.defaultProfileName, color: 0)]
        profiles = list
        let active = UserDefaults.standard.object(forKey: activeKey) as? Int ?? 0
        activeId = list.contains { $0.id == active } ? active : list[0].id
        unlocked = !(list.first { $0.id == active }?.locked ?? false)
    }

    var active: Profile { profiles.first { $0.id == activeId } ?? profiles[0] }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: key) }
        UserDefaults.standard.set(activeId, forKey: activeKey)
    }

    func nameValid(_ name: String, except: Int? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 20 && !profiles.contains { $0.id != except && $0.name.lowercased() == trimmed.lowercased() }
    }

    @discardableResult
    func add(_ name: String) -> Profile? {
        guard nameValid(name) else { return nil }
        let id = (profiles.map(\.id).max() ?? -1) + 1
        let profile = Profile(id: id, name: name.trimmingCharacters(in: .whitespaces), color: id % ProfileColors.all.count)
        profiles.append(profile)
        save()
        return profile
    }

    func rename(_ id: Int, _ name: String) {
        guard nameValid(name, except: id), let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = name.trimmingCharacters(in: .whitespaces)
        save()
    }

    func setPin(_ id: Int, _ pin: String?) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let pin {
            let salt = ProfilePin.newSalt()
            profiles[i].pinSalt = salt
            profiles[i].pinHash = ProfilePin.hash(pin, salt: salt)
        } else {
            profiles[i].pinSalt = nil
            profiles[i].pinHash = nil
        }
        save()
    }

    /// Etkin profil ve son kalan profil silinemez; verisi de silinir.
    func delete(_ id: Int) {
        guard id != activeId, profiles.count > 1, let profile = profiles.first(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: LibraryStore.fileURL(profile.fileName))
        save()
    }

    /// Profile geçer (PIN'liyse çağıran doğrulamış olmalı).
    func activate(_ id: Int, store: LibraryStore) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeId = id
        unlocked = true
        save()
        store.load(fileName: profile.fileName)
    }
}

/// Baş harf, renkli dairede.
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 32

    var body: some View {
        Text(String(profile.name.prefix(1)).uppercaseTr)
            .font(Theme.title(size * 0.45))
            .foregroundStyle(Color(red: 0x1B / 255, green: 0x14 / 255, blue: 0x16 / 255))
            .frame(width: size, height: size)
            .background(ProfileColors.all[profile.color % ProfileColors.all.count], in: Circle())
    }
}
