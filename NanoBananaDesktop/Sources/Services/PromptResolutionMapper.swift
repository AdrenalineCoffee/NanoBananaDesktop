import Foundation

final class PromptResolutionMapper {
    private let oneKKeywords = ["low resolution", "1080", "1080p", "1k"]
    private let twoKKeywords = ["2k", "2048", "normal", "medium resolution"]
    private let fourKKeywords = ["high resolution", "high-res", "hi-res", "4k", "ultra"]

    func resolve(prompt: String, selection: ResolutionSelection) -> ImageResolution {
        if let manual = selection.manualResolution {
            return manual
        }

        let normalized = prompt.lowercased()

        if containsAnyKeyword(in: normalized, keywords: fourKKeywords) {
            return .k4
        }

        if containsAnyKeyword(in: normalized, keywords: twoKKeywords) {
            return .k2
        }

        if containsAnyKeyword(in: normalized, keywords: oneKKeywords) {
            return .k1
        }

        return .k1
    }

    private func containsAnyKeyword(in text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
