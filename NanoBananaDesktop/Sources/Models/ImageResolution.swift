import Foundation

enum ImageResolution: String, Codable, CaseIterable, Identifiable {
    case k1 = "1K"
    case k2 = "2K"
    case k4 = "4K"

    var id: String { rawValue }
}
