import Foundation

enum ResolutionSelection: String, Codable, CaseIterable, Identifiable {
    case auto
    case k1
    case k2
    case k4

    var id: String { rawValue }

    var manualResolution: ImageResolution? {
        switch self {
        case .auto:
            return nil
        case .k1:
            return .k1
        case .k2:
            return .k2
        case .k4:
            return .k4
        }
    }
}
