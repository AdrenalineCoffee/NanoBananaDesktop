import Foundation

enum ImageAspectRatio: String, Codable, CaseIterable, Identifiable {
    case square = "1:1"
    case landscape4x3 = "4:3"
    case portrait3x4 = "3:4"
    case landscape3x2 = "3:2"
    case portrait2x3 = "2:3"
    case landscape16x9 = "16:9"
    case portrait9x16 = "9:16"
    case landscape21x9 = "21:9"
    case portrait9x21 = "9:21"

    var id: String { rawValue }

    var components: (width: Double, height: Double) {
        switch self {
        case .square:
            return (1, 1)
        case .landscape4x3:
            return (4, 3)
        case .portrait3x4:
            return (3, 4)
        case .landscape3x2:
            return (3, 2)
        case .portrait2x3:
            return (2, 3)
        case .landscape16x9:
            return (16, 9)
        case .portrait9x16:
            return (9, 16)
        case .landscape21x9:
            return (21, 9)
        case .portrait9x21:
            return (9, 21)
        }
    }

    var numericValue: Double {
        let components = components
        return components.width / components.height
    }

    static func closest(forWidth width: Double, height: Double) -> ImageAspectRatio {
        guard width > 0, height > 0 else {
            return .square
        }

        let sourceRatio = width / height
        return allCases.min(by: { abs($0.numericValue - sourceRatio) < abs($1.numericValue - sourceRatio) }) ?? .square
    }
}

enum AspectRatioSelection: String, Codable, CaseIterable, Identifiable {
    case auto
    case square
    case landscape4x3
    case portrait3x4
    case landscape3x2
    case portrait2x3
    case landscape16x9
    case portrait9x16
    case landscape21x9
    case portrait9x21

    var id: String { rawValue }

    var manualAspectRatio: ImageAspectRatio? {
        switch self {
        case .auto:
            return nil
        case .square:
            return .square
        case .landscape4x3:
            return .landscape4x3
        case .portrait3x4:
            return .portrait3x4
        case .landscape3x2:
            return .landscape3x2
        case .portrait2x3:
            return .portrait2x3
        case .landscape16x9:
            return .landscape16x9
        case .portrait9x16:
            return .portrait9x16
        case .landscape21x9:
            return .landscape21x9
        case .portrait9x21:
            return .portrait9x21
        }
    }
}
