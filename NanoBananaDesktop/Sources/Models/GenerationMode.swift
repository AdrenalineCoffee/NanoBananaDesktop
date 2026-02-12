import Foundation

enum GenerationMode: String, Codable, CaseIterable, Identifiable {
    case generate
    case edit

    var id: String { rawValue }
}
