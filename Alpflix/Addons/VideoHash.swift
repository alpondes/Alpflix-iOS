import Foundation

/// Oynatılan dosyanın OpenSubtitles parmak izi ve boyu: altyazı eklentileri bununla aynı sürüme ait
/// (kaymayan) altyazıyı öne alır. Dosyanın tamamı indirilmez: baştan ve sondan birer 64 KB'lik
/// aralık isteği (indirilen dosyada doğrudan okuma). Kaynak adresi log'lanmaz.
struct VideoFingerprint: Hashable {
    let hash: String
    let size: Int64
}

enum VideoHash {
    static let chunk = 65_536

    /// Boy + ilk ve son 64 KB'nin küçük-endian 64 bitlik sözcüklerinin toplamı (taşma serbest).
    static func compute(size: Int64, head: Data, tail: Data) -> String? {
        guard size >= Int64(chunk * 2), head.count >= chunk, tail.count >= chunk else { return nil }
        let sum = UInt64(bitPattern: size) &+ checksum(head) &+ checksum(tail)
        return String(format: "%016llx", sum)
    }

    private static func checksum(_ data: Data) -> UInt64 {
        var sum: UInt64 = 0
        let bytes = [UInt8](data.prefix(chunk))
        var i = 0
        while i + 8 <= chunk {
            var word: UInt64 = 0
            for b in stride(from: 7, through: 0, by: -1) { word = (word << 8) | UInt64(bytes[i + b]) }
            sum = sum &+ word
            i += 8
        }
        return sum
    }

    /// "bytes 0-65535/1234567" → 1234567.
    static func total(contentRange: String?) -> Int64? {
        guard let value = contentRange?.split(separator: "/").last, let total = Int64(value.trimmingCharacters(in: .whitespaces)), total > 0 else { return nil }
        return total
    }

    /// Uzak ya da yerel dosyanın parmak izi; aralık desteklenmezse ya da 8 sn'de bitmezse nil.
    static func fingerprint(_ url: URL) async -> VideoFingerprint? {
        if url.isFileURL { return local(url) }
        guard let first = await range(url, from: 0, to: Int64(chunk - 1)),
              let size = first.1, size >= Int64(chunk * 2) else { return nil }
        guard let last = await range(url, from: size - Int64(chunk), to: size - 1) else { return nil }
        return compute(size: size, head: first.0, tail: last.0).map { VideoFingerprint(hash: $0, size: size) }
    }

    private static func local(_ url: URL) -> VideoFingerprint? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= UInt64(chunk * 2) else { return nil }
        try? handle.seek(toOffset: 0)
        guard let head = try? handle.read(upToCount: chunk) else { return nil }
        try? handle.seek(toOffset: size - UInt64(chunk))
        guard let tail = try? handle.read(upToCount: chunk) else { return nil }
        let total = Int64(size)
        return compute(size: total, head: head, tail: tail).map { VideoFingerprint(hash: $0, size: total) }
    }

    /// Aralık isteği: (baytlar, toplam boy). 206 dışı yanıtta (tüm dosya gelir) bırakılır.
    private static func range(_ url: URL, from: Int64, to: Int64) async -> (Data, Int64?)? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 206 else { return nil }
        let expected = Int(to - from + 1)
        var data = Data(capacity: expected)
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= expected { break }
            }
        } catch {
            return nil
        }
        guard data.count >= expected else { return nil }
        return (data, total(contentRange: http.value(forHTTPHeaderField: "Content-Range")))
    }
}
