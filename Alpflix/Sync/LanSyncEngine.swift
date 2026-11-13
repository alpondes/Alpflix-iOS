import Combine
import CryptoKit
import Foundation
import Network
import UIKit

enum SyncError: Error {
    case closed, timeout, badFrame
}

/// Uzunluk önekli çerçeveler (4 bayt big-endian + içerik) ve bağlantı yardımcıları.
enum FrameIO {
    /// Durum dinleyicisi kurulup bağlantı başlatılır; hazır olunca döner.
    static func start(_ connection: NWConnection, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error), .waiting(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: SyncError.closed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    static func send(_ connection: NWConnection, _ payload: Data) async throws {
        let size = UInt32(payload.count)
        var frame = Data([UInt8(size >> 24 & 0xff), UInt8(size >> 16 & 0xff), UInt8(size >> 8 & 0xff), UInt8(size & 0xff)])
        frame.append(payload)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    static func readFrame(_ connection: NWConnection) async throws -> Data {
        let header = try await receive(connection, 4)
        let bytes = [UInt8](header)
        let size = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard size > 0, size <= SyncCrypto.maxFrame else { throw SyncError.badFrame }
        return try await receive(connection, size)
    }

    private static func receive(_ connection: NWConnection, _ count: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: count - buffer.count) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: SyncError.closed)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }

    /// [seconds] içinde bitmezse bağlantı kapatılır (bekleyen okuma hata ile döner).
    static func withTimeout<T>(_ connection: NWConnection, seconds: Double, _ operation: () async throws -> T) async throws -> T {
        let guardTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { connection.cancel() }
        }
        defer { guardTask.cancel() }
        return try await operation()
    }
}

/// Wi-Fi eşitlemesi (Android ile aynı protokol): uygulama ön plandayken ağda "_alpflix._tcp" olarak
/// duyurulur, aynı eşleştirme kodlu cihazları arar ve kaldığın yerleri, izlemeleri, silmeleri, durumları ve
/// "İzlemeye devam et"ten kaldırmaları karşılıklı birleştirir. Bulut/hesap yok; trafik AES-GCM şifreli.
@MainActor
final class LanSyncEngine: ObservableObject {
    static let shared = LanSyncEngine()
    static let serviceType = "_alpflix._tcp"

    struct Peer: Identifiable {
        let id: String
        var name: String
        let endpoint: NWEndpoint
        var lastSync: Date?
    }

    enum Problem {
        case profileMismatch, locked, connection
    }

    @Published private(set) var paired = false
    @Published private(set) var running = false
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastPeerName: String?
    @Published private(set) var lastChanges = 0
    @Published private(set) var problem: Problem?

    private weak var store: LibraryStore?
    private weak var profiles: ProfileStore?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var timer: Timer?
    private var changes: AnyCancellable?
    private var lastFingerprint = ""
    private var busy = false
    private var active = false
    private let queue = DispatchQueue(label: "alpflix.sync")
    private let defaults = UserDefaults.standard

    private init() {
        paired = defaults.string(forKey: Keys.code) != nil
        let last = defaults.double(forKey: Keys.last)
        lastSync = last > 0 ? Date(timeIntervalSince1970: last) : nil
    }

    private enum Keys {
        static let code = "local_sync_code"
        static let device = "local_sync_device"
        static let last = "sync_last"
        static let peerPrefix = "sync_peer_"
    }

    var deviceId: String {
        if let id = defaults.string(forKey: Keys.device) { return id }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(id, forKey: Keys.device)
        return id
    }

    private var shortId: String { String(deviceId.prefix(8)) }
    private var deviceName: String { UIDevice.current.name }
    private var key: SymmetricKey? { defaults.string(forKey: Keys.code).map(SyncCrypto.key) }

    var currentCode: String? { defaults.string(forKey: Keys.code) }

    // MARK: Kurulum

    func configure(store: LibraryStore, profiles: ProfileStore) {
        self.store = store
        self.profiles = profiles
        // Yerel değişiklik: 4 sn birikmeyle öbür cihazlara.
        changes = store.$data
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.localChanged() }
    }

    func setActive(_ on: Bool) {
        active = on
        if on { start() } else { stop() }
    }

    // MARK: Eşleştirme

    func createCode() -> String {
        let code = SyncCrypto.newCode()
        savePairing(code)
        return code
    }

    func enterCode(_ input: String) -> Bool {
        guard let normalized = SyncCrypto.normalize(input) else { return false }
        savePairing(SyncCrypto.formatted(normalized))
        return true
    }

    func unpair() {
        defaults.removeObject(forKey: Keys.code)
        stop()
        paired = false
        problem = nil
    }

    private func savePairing(_ code: String) {
        defaults.set(code, forKey: Keys.code)
        paired = true
        problem = nil
        stop()
        if active { start() }
    }

    func syncNow() {
        Task { await syncAll(initiatorOnly: false) }
    }

    // MARK: Ağ

    private func start() {
        guard listener == nil, let key else { return }
        let group = SyncCrypto.group(key)
        guard let listener = try? NWListener(using: .tcp) else { return }
        listener.service = NWListener.Service(name: SyncCrypto.serviceName(group: group, device: deviceId), type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in await self?.serve(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.map(\.endpoint)
            Task { @MainActor in self?.update(endpoints, group: group) }
        }
        browser.start(queue: queue)
        self.browser = browser
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncAll(initiatorOnly: true) }
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        timer?.invalidate()
        timer = nil
        peers = []
        running = false
    }

    private func update(_ endpoints: [NWEndpoint], group: String) {
        var found: [Peer] = []
        for endpoint in endpoints {
            guard case let .service(name, _, _, _) = endpoint,
                  let parsed = SyncCrypto.parseServiceName(name), parsed.group == group, parsed.device != shortId else { continue }
            let old = peers.first { $0.id == parsed.device }
            found.append(Peer(id: parsed.device, name: old?.name ?? parsed.device, endpoint: endpoint,
                              lastSync: old?.lastSync ?? storedPeerSync(parsed.device)))
        }
        let newOnes = found.filter { f in !peers.contains { $0.id == f.id } }
        peers = found.sorted { $0.name < $1.name }
        for peer in newOnes where shortId < peer.id {
            Task { await sync(peer) }
        }
    }

    private func storedPeerSync(_ id: String) -> Date? {
        let value = defaults.double(forKey: Keys.peerPrefix + id)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private func localChanged() {
        guard active, let store else { return }
        let fingerprint = store.syncFingerprint
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        Task { await syncAll(initiatorOnly: false) }
    }

    private func syncAll(initiatorOnly: Bool) async {
        for peer in peers where !initiatorOnly || shortId < peer.id {
            await sync(peer)
        }
    }

    private func localDoc() -> SyncDoc? {
        guard let store, let profiles else { return nil }
        return store.syncDoc(device: deviceId, deviceName: deviceName, profile: profiles.active.name)
    }

    private func encode(_ doc: SyncDoc, key: SymmetricKey) throws -> Data {
        try SyncCrypto.seal(try JSONEncoder().encode(doc), key: key)
    }

    private func decode(_ frame: Data, key: SymmetricKey) -> SyncDoc? {
        guard let plain = SyncCrypto.open(frame, key: key) else { return nil }
        return try? JSONDecoder().decode(SyncDoc.self, from: plain)
    }

    /// Bu cihaz başlatır: belgesini gönderir, karşının (birleştirilmiş) belgesini alıp uygular.
    private func sync(_ peer: Peer) async {
        guard !busy, let key, let profiles else { return }
        guard profiles.unlocked else {
            problem = .locked
            return
        }
        guard let doc = localDoc(), let payload = try? encode(doc, key: key) else { return }
        busy = true
        defer { busy = false }
        let connection = NWConnection(to: peer.endpoint, using: .tcp)
        let queue = self.queue
        do {
            let reply = try await FrameIO.withTimeout(connection, seconds: 20) {
                try await FrameIO.start(connection, queue: queue)
                try await FrameIO.send(connection, payload)
                return try await FrameIO.readFrame(connection)
            }
            connection.cancel()
            guard let incoming = decode(reply, key: key) else { throw SyncError.badFrame }
            handle(incoming, peerId: peer.id)
        } catch {
            connection.cancel()
            problem = .connection
        }
    }

    /// Öbür cihaz başlattı: belgesini al, uygula, kendi belgeni gönder.
    private func serve(_ connection: NWConnection) async {
        guard let key else {
            connection.cancel()
            return
        }
        let queue = self.queue
        do {
            let frame = try await FrameIO.withTimeout(connection, seconds: 20) {
                try await FrameIO.start(connection, queue: queue)
                return try await FrameIO.readFrame(connection)
            }
            guard let incoming = decode(frame, key: key) else { throw SyncError.badFrame }
            guard profiles?.unlocked == true else {
                problem = .locked
                connection.cancel()
                return
            }
            handle(incoming, peerId: String(incoming.device.prefix(8)))
            if let doc = localDoc(), let payload = try? encode(doc, key: key) {
                try await FrameIO.withTimeout(connection, seconds: 20) { try await FrameIO.send(connection, payload) }
            }
        } catch {
            problem = .connection
        }
        // Gönderilenin karşıya ulaşması için kısa bekleyip kapat.
        try? await Task.sleep(nanoseconds: 500_000_000)
        connection.cancel()
    }

    private func handle(_ incoming: SyncDoc, peerId: String) {
        guard let store, let profiles else { return }
        if let i = peers.firstIndex(where: { $0.id == peerId }), !incoming.deviceName.isEmpty { peers[i].name = incoming.deviceName }
        guard incoming.v == 1, SyncMerge.sameProfile(incoming.profile, profiles.active.name) else {
            problem = .profileMismatch
            return
        }
        let local = store.syncDoc(device: deviceId, deviceName: deviceName, profile: profiles.active.name)
        lastChanges = store.applySync(incoming, local: local)
        lastFingerprint = store.syncFingerprint
        let now = Date()
        lastSync = now
        lastPeerName = incoming.deviceName.isEmpty ? nil : incoming.deviceName
        problem = nil
        defaults.set(now.timeIntervalSince1970, forKey: Keys.last)
        defaults.set(now.timeIntervalSince1970, forKey: Keys.peerPrefix + peerId)
        if let i = peers.firstIndex(where: { $0.id == peerId }) { peers[i].lastSync = now }
    }
}
