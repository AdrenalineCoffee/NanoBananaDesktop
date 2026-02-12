import Foundation

final class FilenameGenerator {
    private let fileManager: FileManager
    private let now: () -> Date

    init(fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    func generateFilename(prompt: String, outputDirectory: URL) -> String {
        let timestamp = timestampString(from: now())
        let slug = slugify(prompt)
        let baseName = "\(timestamp)-\(slug)"
        return uniqueFilename(baseName: baseName, outputDirectory: outputDirectory)
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: date)
    }

    private func slugify(_ prompt: String) -> String {
        let lowercased = prompt.lowercased()
        let sanitized = lowercased.replacingOccurrences(
            of: "[^a-z0-9\\s-]",
            with: " ",
            options: .regularExpression
        )

        let words = sanitized
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        let selectedWords = Array(words.prefix(5))
        if selectedWords.isEmpty {
            return randomToken()
        }

        return selectedWords.joined(separator: "-")
    }

    private func randomToken(length: Int = 4) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    private func uniqueFilename(baseName: String, outputDirectory: URL) -> String {
        var candidate = "\(baseName).png"
        var index = 1

        while fileManager.fileExists(atPath: outputDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(baseName)-\(index).png"
            index += 1
        }

        return candidate
    }
}
