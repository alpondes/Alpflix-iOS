import Foundation

/// Kaynak adından okunanlar (Torrentio biçimi: "Torrentio\n4k DV | HDR", "💾 12.3 GB ⚙️ …", "[RD+]").
struct StreamInfo: Hashable {
    let resolution: Int
    let sizeGB: Double?
    let cached: Bool
    let tags: [String]
    let torrentOnly: Bool

    static func parse(_ stream: AddonStream) -> StreamInfo {
        let text = [stream.name, stream.title, stream.description, stream.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: " ")
        let lower = text.lowercased()
        let resolution: Int
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") {
            resolution = 2160
        } else if lower.contains("1080") {
            resolution = 1080
        } else if lower.contains("720") {
            resolution = 720
        } else if lower.contains("480") || lower.contains("sd") {
            resolution = 480
        } else {
            resolution = 0
        }
        var tags: [String] = []
        if lower.contains("dolby vision") || lower.contains(" dv") || lower.contains("dovi") { tags.append("DV") }
        if lower.contains("hdr") { tags.append("HDR") }
        if lower.contains("hevc") || lower.contains("x265") || lower.contains("h265") { tags.append("HEVC") }
        if lower.contains("atmos") { tags.append("Atmos") }
        if lower.contains("remux") { tags.append("REMUX") }
        let cached = text.contains("+]") || text.contains("⚡") || lower.contains("[rd+") || lower.contains("cached")
        return StreamInfo(
            resolution: resolution,
            sizeGB: size(in: text),
            cached: cached,
            tags: tags,
            torrentOnly: stream.url == nil && stream.infoHash != nil
        )
    }

    /// "12.3 GB" / "850 MB".
    private static func size(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9]+(?:[.,][0-9]+)?)\\s?(GB|MB)", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return text[unitRange].uppercased() == "MB" ? value / 1024 : value
    }

    var resolutionLabel: String {
        switch resolution {
        case 2160: return "4K"
        case 1080: return "1080p"
        case 720: return "720p"
        case 480: return "SD"
        default: return "?"
        }
    }

    /// Sıralama: oynatılabilir ve hazır olanlar önce, sonra çözünürlük, sonra boyut.
    static func sort(_ items: [StreamCandidate]) -> [StreamCandidate] {
        items.sorted { a, b in
            if a.info.torrentOnly != b.info.torrentOnly { return !a.info.torrentOnly }
            if a.info.cached != b.info.cached { return a.info.cached }
            if a.info.resolution != b.info.resolution { return a.info.resolution > b.info.resolution }
            return (a.info.sizeGB ?? 0) > (b.info.sizeGB ?? 0)
        }
    }
}
