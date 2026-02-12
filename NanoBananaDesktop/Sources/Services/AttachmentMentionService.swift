import Foundation

final class AttachmentMentionService {
    func makeMentionToken(fileURL: URL, existingTokens: Set<String>) -> String {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let sanitized = sanitize(baseName)
        let candidate = "@\(sanitized)"

        if !existingTokens.contains(candidate) {
            return candidate
        }

        var suffix = 2
        while existingTokens.contains("\(candidate)_\(suffix)") {
            suffix += 1
        }
        return "\(candidate)_\(suffix)"
    }

    private func sanitize(_ value: String) -> String {
        let lowered = value.lowercased()
        let replacedWhitespace = lowered.replacingOccurrences(
            of: "\\s+",
            with: "_",
            options: .regularExpression
        )

        var output = ""
        var previousUnderscore = false

        for scalar in replacedWhitespace.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousUnderscore = false
            } else if scalar == "_" {
                if !previousUnderscore {
                    output.unicodeScalars.append(scalar)
                    previousUnderscore = true
                }
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "file" : trimmed
    }
}
