import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func generationCostRegistryEstimatesKieCredits() {
    let estimate = GenerationCostRegistry.estimate(
        provider: .kie,
        model: "kie:nano-banana-pro",
        resolution: .k2,
        imageCount: 2
    )

    #expect(estimate.unit == .kieCredits)
    #expect(estimate.confidence == .estimated)
    #expect(estimate.total == 200)
}

@Test
func generationCostRegistryEstimatesOpenAIUSD() {
    let estimate = GenerationCostRegistry.estimate(
        provider: .openAI,
        model: "gpt-image-2",
        resolution: .k4,
        imageCount: 4
    )

    #expect(estimate.unit == .usd)
    #expect(estimate.total == 1.0)
}

@Test
func generationCostRegistryReturnsUnavailableForUnknownGatewayModel() {
    let estimate = GenerationCostRegistry.estimate(
        provider: .openAICompatible,
        model: "openAICompatible:custom-renderer",
        resolution: .k1,
        imageCount: 1
    )

    #expect(estimate.unit == .unknown)
    #expect(estimate.confidence == .unavailable)
    #expect(estimate.total == nil)
}

@Test
func generationCostRegistryCombinesActualKieImageCosts() {
    let images = [
        GeneratedImageResult(imageData: Data([1]), modelText: nil, cost: GenerationCostRegistry.actualKieCredits(model: "nano-banana-pro", resolution: .k1, imageCount: 1, totalCredits: 10)),
        GeneratedImageResult(imageData: Data([2]), modelText: nil, cost: GenerationCostRegistry.actualKieCredits(model: "nano-banana-pro", resolution: .k1, imageCount: 1, totalCredits: 15))
    ]
    let fallback = GenerationCostRegistry.estimate(provider: .kie, model: "nano-banana-pro", resolution: .k1, imageCount: 2)

    let actual = GenerationCostRegistry.combinedActualCost(from: images, fallback: fallback)

    #expect(actual?.confidence == .actual)
    #expect(actual?.total == 25)
    #expect(actual?.perImage == 12.5)
}

@Test
func generationCostRegistryDisplaysCreditCurrencyConversion() {
    let estimate = GenerationCostRegistry.actualKieCredits(
        model: "nano-banana-pro",
        resolution: .k1,
        imageCount: 1,
        totalCredits: 25
    )
    let conversion = CreditCostConversion(currency: .rub, costPer100Credits: 120)

    let text = GenerationCostRegistry.compactDisplayText(
        for: estimate,
        language: .ru,
        creditConversion: conversion
    )

    #expect(text == "25 Kie credits (~30.00 RUB)")
}

@Test
func generationCostRegistryBuildsPerImageCostFromTotal() {
    let estimate = GenerationCostRegistry.actualKieCredits(
        model: "nano-banana-pro",
        resolution: .k1,
        imageCount: 4,
        totalCredits: 100
    )

    let perImage = GenerationCostRegistry.perImageCost(from: estimate)

    #expect(perImage?.imageCount == 1)
    #expect(perImage?.total == 25)
    #expect(perImage?.perImage == 25)
}
