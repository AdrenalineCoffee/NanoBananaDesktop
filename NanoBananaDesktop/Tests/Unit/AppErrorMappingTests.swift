import Testing
@testable import NanoBananaDesktop

@Test
func billingCreditsDepletedMessageMapsToDedicatedError() {
    let message = """
    RESOURCE_EXHAUSTED: 429: Your prepayment credits are depleted. Please go to AI Studio at https://ai.studio/projects to manage your project and billing. Learn more at https://ai.google.dev/gemini-api/docs/billing#prepay.
    """

    let error = AppError.billingCreditsDepletedError(message: message)

    if case .billingCreditsDepleted(let details) = error {
        #expect(details.contains("prepayment credits are depleted"))
        #expect(details.contains("billing#prepay"))
    } else {
        Issue.record("Expected dedicated billing credits error")
    }
}

@Test
func resourceExhaustedQuotaMessageMapsToQuotaError() {
    let error = AppError.quotaError(message: "RESOURCE_EXHAUSTED: Quota exceeded")

    #expect(error == .quotaExceeded)
}
