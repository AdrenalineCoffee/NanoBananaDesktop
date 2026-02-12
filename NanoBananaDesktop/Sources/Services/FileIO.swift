import Foundation

enum FileIO {
    static func writeAtomically(data: Data, to url: URL, permissions: Int16 = 0o600, fileManager: FileManager = .default) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".tmp-\(UUID().uuidString)-\(url.lastPathComponent)", isDirectory: false)
        try data.write(to: temporaryURL, options: [.atomic])

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.moveItem(at: temporaryURL, to: url)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: url.path)
    }
}
