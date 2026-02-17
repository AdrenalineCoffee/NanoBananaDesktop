import Testing
@testable import NanoBananaDesktop

@Test
func imagePreviewLayoutMapsThreeToTwoPlusOne() {
    #expect(ImagePreviewLayout.rows(for: 3) == [[0, 1], [2]])
}

@Test
func imagePreviewLayoutMapsFourToTwoByTwo() {
    #expect(ImagePreviewLayout.rows(for: 4) == [[0, 1], [2, 3]])
}

@Test
func imagePreviewLayoutClampsCountAboveFour() {
    #expect(ImagePreviewLayout.rows(for: 7) == [[0, 1], [2, 3]])
}
