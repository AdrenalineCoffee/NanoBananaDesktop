import AppKit
import Foundation

struct AttachedImage: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let displayName: String
    let mentionToken: String
    let thumbnail: NSImage?

    init(
        id: UUID = UUID(),
        fileURL: URL,
        displayName: String,
        mentionToken: String,
        thumbnail: NSImage?
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.mentionToken = mentionToken
        self.thumbnail = thumbnail
    }

    static func == (lhs: AttachedImage, rhs: AttachedImage) -> Bool {
        lhs.id == rhs.id &&
            lhs.fileURL == rhs.fileURL &&
            lhs.displayName == rhs.displayName &&
            lhs.mentionToken == rhs.mentionToken
    }
}
