import Foundation

final class ImagePersistenceService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func savePNG(imageData: Data, filename: String, outputDirectory: URL) throws -> URL {
        guard outputDirectory.path.hasPrefix("/") else {
            throw AppError.invalidOutputDirectory
        }

        let finalFilename: String
        if filename.lowercased().hasSuffix(".png") {
            finalFilename = filename
        } else {
            finalFilename = "\(filename).png"
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let destination = outputDirectory.appendingPathComponent(finalFilename, isDirectory: false)
        do {
            try imageData.write(to: destination, options: [.atomic])
        } catch {
            throw AppError.ioError(error.localizedDescription)
        }

        return destination
    }
}
