import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func generatesExpectedPatternFromPrompt() throws {
    let fixedDate = try #require(ISO8601DateFormatter().date(from: "2025-11-23T14:23:05Z"))
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let generator = FilenameGenerator(now: { fixedDate })
    let filename = generator.generateFilename(prompt: "A serene Japanese garden", outputDirectory: tempDirectory)
    #expect(filename.hasSuffix("-a-serene-japanese-garden.png"))
    #expect(filename.split(separator: "-").count >= 7)
}

@Test
func fallsBackToRandomTokenWhenPromptHasNoASCIIWords() throws {
    let fixedDate = try #require(ISO8601DateFormatter().date(from: "2025-11-23T17:12:48Z"))
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let generator = FilenameGenerator(now: { fixedDate })
    let filename = generator.generateFilename(prompt: "картинка", outputDirectory: tempDirectory)
    #expect(filename.hasSuffix(".png"))
    #expect(filename.contains("-"))
}

@Test
func addsNumericSuffixWhenFilenameAlreadyExists() throws {
    let fixedDate = try #require(ISO8601DateFormatter().date(from: "2025-11-23T17:12:48Z"))
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let generator = FilenameGenerator(now: { fixedDate })
    let first = generator.generateFilename(prompt: "sunset mountains", outputDirectory: tempDirectory)
    let firstURL = tempDirectory.appendingPathComponent(first)
    FileManager.default.createFile(atPath: firstURL.path, contents: Data())

    let second = generator.generateFilename(prompt: "sunset mountains", outputDirectory: tempDirectory)
    #expect(first != second)
    #expect(second.contains("-1.png"))
}
