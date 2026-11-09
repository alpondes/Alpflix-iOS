import Foundation

/// Basit ZIP okuyucu (Trakt dışa aktarımı): merkez dizinden dosyalar; saklanmış (0) ve DEFLATE (8)
/// sıkıştırma. ZIP64 ve şifreli arşiv desteklenmez. Açılan toplam boyut sınırlı (zip bombası koruması).
enum ZipReader {
    static let maxTotalBytes = 64 * 1024 * 1024

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03 && data[data.startIndex + 3] == 0x04
    }

    /// (dosya adı, içerik) çiftleri; yalnız [extensions] uzantılılar.
    static func files(_ data: Data, extensions: Set<String> = ["json"]) -> [(name: String, data: Data)] {
        let bytes = [UInt8](data)
        guard let end = findEnd(bytes) else { return [] }
        let count = u16(bytes, end + 10)
        var offset = Int(u32(bytes, end + 16))
        var result: [(name: String, data: Data)] = []
        var total = 0
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x02014b50 else { break }
            let flags = u16(bytes, offset + 8)
            let method = u16(bytes, offset + 10)
            let compressed = Int(u32(bytes, offset + 20))
            let size = Int(u32(bytes, offset + 24))
            let nameLength = u16(bytes, offset + 28)
            let extraLength = u16(bytes, offset + 30)
            let commentLength = u16(bytes, offset + 32)
            let local = Int(u32(bytes, offset + 42))
            let nameEnd = offset + 46 + nameLength
            guard nameEnd <= bytes.count else { break }
            let fullName = String(decoding: bytes[(offset + 46)..<nameEnd], as: UTF8.self)
            offset = nameEnd + extraLength + commentLength
            let name = (fullName as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension.lowercased()
            guard !fullName.hasSuffix("/"), !name.hasPrefix("."), extensions.contains(ext), flags & 0x1 == 0 else { continue }
            guard local + 30 <= bytes.count, u32(bytes, local) == 0x04034b50 else { continue }
            let start = local + 30 + u16(bytes, local + 26) + u16(bytes, local + 28)
            guard start + compressed <= bytes.count, total + size <= maxTotalBytes else { continue }
            let body = Data(bytes[start..<(start + compressed)])
            let content: Data?
            switch method {
            case 0: content = body
            case 8: content = try? (body as NSData).decompressed(using: .zlib) as Data
            default: content = nil
            }
            guard let content else { continue }
            total += content.count
            result.append((name, content))
        }
        return result
    }

    private static func findEnd(_ b: [UInt8]) -> Int? {
        guard b.count >= 22 else { return nil }
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_535)
        while i >= stop {
            if u32(b, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int {
        guard i + 1 < b.count else { return 0 }
        return Int(b[i]) | (Int(b[i + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}
