import Foundation

/// Uzak altyazıyı cihaza .srt/.vtt dosyası olarak yazar: çoğu adres uzantısız, bazıları gzip;
/// Türkçe altyazılarda yaygın Windows-1254 UTF-8'e çevrilir. VLC dosyayı uzantısından tanır.
enum SubtitleFiles {
    static func save(_ url: URL, in directory: URL, name: String) async -> URL? {
        guard url.scheme?.hasPrefix("http") == true,
              var data = try? await HTTP.data(url, timeout: 30),
              !data.isEmpty, data.count < 8_000_000 else { return nil }
        if data.count > 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b {
            guard let unzipped = AndroidBackup.gunzip(data) else { return nil }
            data = unzipped
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1254) else { return nil }
        let ext = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") ? "vtt" : "srt"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name).\(ext)")
        do {
            try Data(text.utf8).write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }
}
