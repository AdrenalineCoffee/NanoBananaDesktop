import Foundation

final class HistoryStore {
    private let historyURL: URL
    private let fileManager: FileManager
    private let maxRecords: Int?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(historyURL: URL? = nil, fileManager: FileManager = .default, maxRecords: Int? = nil) throws {
        self.fileManager = fileManager
        self.historyURL = try historyURL ?? AppDirectories.historyFileURL(fileManager: fileManager)
        if let maxRecords, maxRecords > 0 {
            self.maxRecords = maxRecords
        } else {
            self.maxRecords = nil
        }

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [HistoryRecord] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyURL)
            let decoded = try decoder.decode([HistoryRecord].self, from: data)
            return normalized(decoded)
        } catch {
            backupCorruptedHistoryIfNeeded()
            return []
        }
    }

    func append(_ record: HistoryRecord) throws {
        var records = load()
        records.insert(record, at: 0)
        try save(records)
    }

    private func save(_ records: [HistoryRecord]) throws {
        let trimmed = normalized(records)
        do {
            let data = try encoder.encode(trimmed)
            try FileIO.writeAtomically(data: data, to: historyURL, fileManager: fileManager)
        } catch {
            throw AppError.ioError(error.localizedDescription)
        }
    }

    private func normalized(_ records: [HistoryRecord]) -> [HistoryRecord] {
        let sorted = records.sorted { $0.timestamp > $1.timestamp }
        guard let maxRecords else {
            return sorted
        }
        return Array(sorted.prefix(maxRecords))
    }

    private func backupCorruptedHistoryIfNeeded() {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupURL = historyURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")

        try? fileManager.moveItem(at: historyURL, to: backupURL)
    }
}
