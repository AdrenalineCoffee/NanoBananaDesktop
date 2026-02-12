import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func mentionTokenUsesSanitizedFilename() {
    let service = AttachmentMentionService()
    let url = URL(fileURLWithPath: "/tmp/Face Reference 01.png")
    let token = service.makeMentionToken(fileURL: url, existingTokens: Set<String>())
    #expect(token == "@face_reference_01")
}

@Test
func mentionTokenAddsNumericSuffixWhenTaken() {
    let service = AttachmentMentionService()
    let url = URL(fileURLWithPath: "/tmp/file.png")
    let token = service.makeMentionToken(fileURL: url, existingTokens: Set(["@file"]))
    #expect(token == "@file_2")
}

@Test
func mentionTokenSupportsCyrillicAndWhitespace() {
    let service = AttachmentMentionService()
    let url = URL(fileURLWithPath: "/tmp/Лицо образец 2.jpeg")
    let token = service.makeMentionToken(fileURL: url, existingTokens: Set<String>())
    #expect(token == "@лицо_образец_2")
}
