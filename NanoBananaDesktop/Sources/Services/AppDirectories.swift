import Foundation

enum AppDirectories {
    static let appFolderName = "NanoBananaDesktop"

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.ioError("Unable to resolve Application Support directory.")
        }

        let directory = baseDirectory.appendingPathComponent(appFolderName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func configFileURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    static func historyFileURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
