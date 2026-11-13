import CryptoKit
import Foundation

// Wi-Fi eşitlemesi: Android ile aynı belge ("v": 1), aynı birleştirme kuralları ve aynı şifreleme.
// Zamanlar ms (Int64). Android tarafı: domain/sync (SyncDoc, SyncMerge, SyncCrypto).

struct SyncDoc: Codable {
    var v: Int = 1
    var device: String
    var deviceName: String = ""
    var profile: String
    var progress: [SyncProgress] = []
    var events: [SyncEvent] = []
    var eventDeletions: [SyncDeletion] = []
    var statuses: [SyncStatus] = []
    var dismissed: [SyncDismissal] = []

    private enum CodingKeys: String, CodingKey {
        case v, device, deviceName, profile, progress, events, eventDeletions, statuses, dismissed
    }

    init(device: String, deviceName: String, profile: String) {
        self.device = device
        self.deviceName = deviceName
        self.profile = profile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decode(Int.self, forKey: .v)) ?? 1
        device = try c.decode(String.self, forKey: .device)
        deviceName = (try? c.decodeIfPresent(String.self, forKey: .deviceName)) ?? ""
        profile = try c.decode(String.self, forKey: .profile)
        progress = (try? c.decodeIfPresent([SyncProgress].self, forKey: .progress)) ?? []
        events = (try? c.decodeIfPresent([SyncEvent].self, forKey: .events)) ?? []
        eventDeletions = (try? c.decodeIfPresent([SyncDeletion].self, forKey: .eventDeletions)) ?? []
        statuses = (try? c.decodeIfPresent([SyncStatus].self, forKey: .statuses)) ?? []
        dismissed = (try? c.decodeIfPresent([SyncDismissal].self, forKey: .dismissed)) ?? []
    }
}

enum SyncKeys {
    static func item(_ type: String, _ tmdbId: Int, _ season: Int?, _ episode: Int?) -> String {
        if let season, let episode { return "\(type):\(tmdbId):\(season):\(episode)" }
        return "\(type):\(tmdbId)"
    }

    static func title(_ type: String, _ tmdbId: Int) -> String { "\(type):\(tmdbId)" }
}

struct SyncProgress: Codable, Hashable {
    var tmdbId: Int
    var type: String
    var season: Int?
    var episode: Int?
    var positionMs: Int64
    var durationMs: Int64
    var updatedAt: Int64
    var title: String = ""
    var poster: String?
    var year: Int?
    var imdbId: String?

    var key: String { SyncKeys.item(type, tmdbId, season, episode) }
}

struct SyncEvent: Codable, Hashable {
    var tmdbId: Int
    var type: String
    var season: Int?
    var episode: Int?
    var watchedAt: Int64

    var key: String { SyncKeys.item(type, tmdbId, season, episode) }
}

/// İzlendi işaretinin kaldırılması: [at] ve öncesindeki aynı film/bölüm izlemeleri silinir.
struct SyncDeletion: Codable, Hashable {
    var tmdbId: Int
    var type: String
    var season: Int?
    var episode: Int?
    var at: Int64

    var key: String { SyncKeys.item(type, tmdbId, season, episode) }
}

/// Kütüphane durumu; status nil: durum kaldırıldı. at: değişiklik zamanı (bilinmiyorsa 0).
struct SyncStatus: Codable, Hashable {
    var tmdbId: Int
    var type: String
    var status: String?
    var at: Int64 = 0
    var title: String = ""
    var poster: String?
    var year: Int?
    var imdbId: String?

    var key: String { SyncKeys.title(type, tmdbId) }
}

struct SyncDismissal: Codable, Hashable {
    var key: String
    var at: Int64
}

extension Date {
    var ms: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
    init(ms: Int64) { self.init(timeIntervalSince1970: TimeInterval(ms) / 1000) }
}

/// Birleştirme (Android SyncMerge ile aynı): kaldığın yerde yeni kazanır; izlemeler birleşir (60 sn içindeki
/// aynı kayıt tek); silmeler birleşir ve eski izlemeleri düşürür; durumda yeni zaman kazanır, yerelde
/// yoksa eklenir; kaldırmalarda en yeni. Silme ve kaldırmalar 180 gün tutulur.
enum SyncMerge {
    static let sameEventMs: Int64 = 60_000
    static let keepMs: Int64 = 180 * 24 * 60 * 60 * 1000

    struct Plan {
        var progressToUpsert: [SyncProgress] = []
        var eventsToAdd: [SyncEvent] = []
        var deletionsToApply: [SyncDeletion] = []
        var statusesToSet: [SyncStatus] = []
        var deletions: [SyncDeletion] = []
        var dismissed: [SyncDismissal] = []

        var changes: Int { progressToUpsert.count + eventsToAdd.count + deletionsToApply.count + statusesToSet.count }
    }

    static func sameProfile(_ a: String, _ b: String) -> Bool { normalize(a) == normalize(b) }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr_TR"))
    }

    static func plan(local: SyncDoc, incoming: SyncDoc, now: Int64) -> Plan {
        var plan = Plan()
        var deletions: [String: SyncDeletion] = [:]
        for d in local.eventDeletions + incoming.eventDeletions where now - d.at <= keepMs {
            if let known = deletions[d.key], known.at >= d.at { continue }
            deletions[d.key] = d
        }
        let localDeletions = Dictionary(local.eventDeletions.map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.at >= b.at ? a : b })
        plan.deletionsToApply = deletions.values.filter { d in
            let known = localDeletions[d.key]
            return (known == nil || known!.at < d.at) && local.events.contains { $0.key == d.key && $0.watchedAt <= d.at }
        }
        func deleted(_ e: SyncEvent) -> Bool { deletions[e.key].map { e.watchedAt <= $0.at } ?? false }

        let localByKey = Dictionary(grouping: local.events, by: \.key)
        for e in incoming.events where !deleted(e) {
            let existing = (localByKey[e.key] ?? []) + plan.eventsToAdd.filter { $0.key == e.key }
            if !existing.contains(where: { abs($0.watchedAt - e.watchedAt) < sameEventMs }) { plan.eventsToAdd.append(e) }
        }

        let localProgress = Dictionary(local.progress.map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        plan.progressToUpsert = incoming.progress.filter { p in
            guard let mine = localProgress[p.key] else { return true }
            return p.updatedAt > mine.updatedAt
        }

        let localStatuses = Dictionary(local.statuses.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        plan.statusesToSet = incoming.statuses.filter { s in
            guard let mine = localStatuses[s.key] else { return s.status != nil }
            return s.at > mine.at && s.status != mine.status
        }

        var dismissed: [String: SyncDismissal] = [:]
        for d in local.dismissed + incoming.dismissed where now - d.at <= keepMs {
            if let known = dismissed[d.key], known.at >= d.at { continue }
            dismissed[d.key] = d
        }
        plan.deletions = Array(deletions.values)
        plan.dismissed = Array(dismissed.values)
        return plan
    }
}

/// Eşleştirme kodu ve şifreleme (Android SyncCrypto ile aynı): anahtar = SHA-256("alpflix-sync-v1:" + kod),
/// grup = SHA-256(anahtar)'ın ilk 4 baytı (onaltılı), çerçeve = 4 bayt uzunluk + nonce + şifreli + etiket (AES-GCM).
enum SyncCrypto {
    private static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
    static let codeLength = 12
    static let maxFrame = 32 * 1024 * 1024

    static func newCode() -> String {
        var generator = SystemRandomNumberGenerator()
        let chars = (0..<codeLength).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }
        return stride(from: 0, to: codeLength, by: 4).map { String(chars[$0..<($0 + 4)]) }.joined(separator: "-")
    }

    static func normalize(_ code: String) -> String? {
        let clean = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard clean.count == codeLength, clean.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return clean
    }

    static func formatted(_ normalized: String) -> String {
        let chars = Array(normalized)
        return stride(from: 0, to: chars.count, by: 4).map { String(chars[$0..<min($0 + 4, chars.count)]) }.joined(separator: "-")
    }

    static func key(_ code: String) -> SymmetricKey {
        let text = "alpflix-sync-v1:" + (normalize(code) ?? code)
        return SymmetricKey(data: Data(SHA256.hash(data: Data(text.utf8))))
    }

    static func group(_ key: SymmetricKey) -> String {
        let raw = key.withUnsafeBytes { Data($0) }
        return SHA256.hash(data: raw).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw CryptoKitError.incorrectParameterSize }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func serviceName(group: String, device: String) -> String { "alpflix-\(group)-\(device.prefix(8))" }

    static func parseServiceName(_ name: String) -> (group: String, device: String)? {
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count == 3, parts[0] == "alpflix" else { return nil }
        return (parts[1], parts[2])
    }
}
