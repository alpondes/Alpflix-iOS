import SwiftUI
import UniformTypeIdentifiers

/// iOS yedeği: bütün veri tek JSON (Dosyalar'a kaydedilir; içe aktarmada geri okunur).
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension LibraryStore {
    func exportData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(data)) ?? Data()
    }

    /// Önce iOS yedeği, olmazsa Android yedeği denenir.
    static func decodeBackup(_ raw: Data) throws -> AppData {
        if let own = try? JSONDecoder().decode(AppData.self, from: raw) { return own }
        return try AndroidBackup.parse(raw)
    }
}
