import Foundation

enum KieModelKind: String, Sendable {
    case textToImage
    case imageToImage
    case upscale
    case removeBackground

    var requiresInputImage: Bool {
        switch self {
        case .textToImage:
            return false
        case .imageToImage, .upscale, .removeBackground:
            return true
        }
    }

    var requiresPrompt: Bool {
        switch self {
        case .textToImage, .imageToImage:
            return true
        case .upscale, .removeBackground:
            return false
        }
    }

    var supportsConcepting: Bool {
        switch self {
        case .imageToImage:
            return true
        case .textToImage, .upscale, .removeBackground:
            return false
        }
    }
}

enum KieImageInputRequirement: Sendable, Equatable {
    case none
    case optional
    case required
}

enum KieImageInputField: Sendable, Equatable {
    case none
    case single(String)
    case array(String)
}

struct KieModelSpec: Sendable, Equatable {
    let model: String
    let displayName: String
    let kind: KieModelKind
    let inputField: KieImageInputField
    let aspectRatioKey: String?
    let resolutionKey: String?
    let imageSizeKey: String?
    let outputFormatKey: String?
    let upscaleFactorKey: String?
    let defaultInput: [String: String]
    let inputRequirement: KieImageInputRequirement

    init(
        model: String,
        displayName: String,
        kind: KieModelKind,
        inputField: KieImageInputField,
        aspectRatioKey: String?,
        resolutionKey: String?,
        imageSizeKey: String?,
        outputFormatKey: String?,
        upscaleFactorKey: String?,
        defaultInput: [String: String],
        inputRequirement: KieImageInputRequirement? = nil
    ) {
        self.model = model
        self.displayName = displayName
        self.kind = kind
        self.inputField = inputField
        self.aspectRatioKey = aspectRatioKey
        self.resolutionKey = resolutionKey
        self.imageSizeKey = imageSizeKey
        self.outputFormatKey = outputFormatKey
        self.upscaleFactorKey = upscaleFactorKey
        self.defaultInput = defaultInput
        if let inputRequirement {
            self.inputRequirement = inputRequirement
        } else if inputField == .none {
            self.inputRequirement = .none
        } else {
            self.inputRequirement = kind.requiresInputImage ? .required : .optional
        }
    }

    var requiresInputImage: Bool {
        inputRequirement == .required
    }

    var supportsInputImage: Bool {
        inputRequirement != .none
    }

    var supportsConcepting: Bool {
        switch kind {
        case .textToImage, .upscale, .removeBackground:
            return false
        case .imageToImage:
            return supportsInputImage
        }
    }

    var catalogItem: ModelCatalogItem {
        ModelCatalogItem(
            provider: .kie,
            name: ModelProvider.encodedModelName(provider: .kie, modelName: model),
            displayName: displayName,
            description: kind.rawValue,
            supportedMethods: ["kie", kind.rawValue],
            isCustomFallback: false
        )
    }
}

enum KieModelRegistry {
    static let specs: [KieModelSpec] = [
        .init(model: "nano-banana-pro", displayName: "Kie Nano Banana Pro", kind: .imageToImage, inputField: .array("image_input"), aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: [:], inputRequirement: .optional),
        .init(model: "nano-banana-2", displayName: "Kie Nano Banana 2", kind: .imageToImage, inputField: .array("image_input"), aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: [:], inputRequirement: .optional),
        .init(model: "google/nano-banana", displayName: "Kie Nano Banana", kind: .textToImage, inputField: .none, aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: "image_size", outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "google/nano-banana-edit", displayName: "Kie Nano Banana Edit", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: "image_size", outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "flux-2/pro-image-to-image", displayName: "Kie Flux-2 Pro Image to Image", kind: .imageToImage, inputField: .array("image_input"), aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "flux-2/pro-text-to-image", displayName: "Kie Flux-2 Pro Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "flux-2/flex-image-to-image", displayName: "Kie Flux-2 Image to Image", kind: .imageToImage, inputField: .array("image_input"), aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "flux-2/flex-text-to-image", displayName: "Kie Flux-2 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "bytedance/seedream", displayName: "Kie Seedream 3.0 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: "image_size", outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "bytedance/seedream-v4-text-to-image", displayName: "Kie Seedream 4.0 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: nil, resolutionKey: "image_resolution", imageSizeKey: "image_size", outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: ["max_images": "1"]),
        .init(model: "bytedance/seedream-v4-edit", displayName: "Kie Seedream 4.0 Edit", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: nil, resolutionKey: "image_resolution", imageSizeKey: "image_size", outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: ["max_images": "1"]),
        .init(model: "seedream/4.5-text-to-image", displayName: "Kie Seedream 4.5 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "seedream/4.5-edit", displayName: "Kie Seedream 4.5 Edit", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "seedream/5-lite-text-to-image", displayName: "Kie Seedream 5.0 Lite Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "seedream/5-lite-image-to-image", displayName: "Kie Seedream 5.0 Lite Image to Image", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "z-image", displayName: "Kie Z-Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "grok-imagine/text-to-image", displayName: "Kie Grok Imagine Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "grok-imagine/image-to-image", displayName: "Kie Grok Imagine Image to Image", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "gpt-image/1.5-text-to-image", displayName: "Kie GPT Image 1.5 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "gpt-image/1.5-image-to-image", displayName: "Kie GPT Image 1.5 Image to Image", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "gpt-image-2-text-to-image", displayName: "Kie GPT Image 2 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "gpt-image-2-image-to-image", displayName: "Kie GPT Image 2 Image to Image", kind: .imageToImage, inputField: .array("input_urls"), aspectRatioKey: "aspect_ratio", resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "ideogram/character-edit", displayName: "Kie Ideogram Character Edit", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "ideogram/character-remix", displayName: "Kie Ideogram Character Remix", kind: .imageToImage, inputField: .array("image_urls"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "ideogram/v3-text-to-image", displayName: "Kie Ideogram V3 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: nil, resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "ideogram/v3-edit", displayName: "Kie Ideogram V3 Edit", kind: .imageToImage, inputField: .single("image"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "ideogram/v3-remix", displayName: "Kie Ideogram V3 Remix", kind: .imageToImage, inputField: .single("image"), aspectRatioKey: nil, resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "qwen/text-to-image", displayName: "Kie Qwen Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: "image_size", outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: ["negative_prompt": " ", "acceleration": "none"]),
        .init(model: "qwen/image-to-image", displayName: "Kie Qwen Image to Image", kind: .imageToImage, inputField: .single("image_url"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: ["strength": "0.8", "negative_prompt": " ", "acceleration": "none"]),
        .init(model: "qwen/image-edit", displayName: "Kie Qwen Image Edit", kind: .imageToImage, inputField: .single("image_url"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: ["negative_prompt": " ", "acceleration": "none"]),
        .init(model: "qwen2/text-to-image", displayName: "Kie Qwen2 Text to Image", kind: .textToImage, inputField: .none, aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: "image_size", outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: ["negative_prompt": " ", "acceleration": "none"]),
        .init(model: "qwen2/image-edit", displayName: "Kie Qwen2 Image Edit", kind: .imageToImage, inputField: .single("image_url"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: "output_format", upscaleFactorKey: nil, defaultInput: ["negative_prompt": " ", "acceleration": "none"]),
        .init(model: "wan/2-7-image", displayName: "Kie Wan 2.7 Image", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "wan/2-7-image-pro", displayName: "Kie Wan 2.7 Image Pro", kind: .textToImage, inputField: .none, aspectRatioKey: "aspect_ratio", resolutionKey: "resolution", imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "topaz/image-upscale", displayName: "Kie Topaz Image Upscale", kind: .upscale, inputField: .single("image_url"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: "upscale_factor", defaultInput: [:]),
        .init(model: "recraft/remove-background", displayName: "Kie Recraft Remove Background", kind: .removeBackground, inputField: .single("image"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:]),
        .init(model: "recraft/crisp-upscale", displayName: "Kie Recraft Crisp Upscale", kind: .upscale, inputField: .single("image"), aspectRatioKey: nil, resolutionKey: nil, imageSizeKey: nil, outputFormatKey: nil, upscaleFactorKey: nil, defaultInput: [:])
    ]

    static var catalogItems: [ModelCatalogItem] {
        specs.map(\.catalogItem)
    }

    static var conceptCatalogItems: [ModelCatalogItem] {
        specs.filter(\.supportsConcepting).map(\.catalogItem)
    }

    static func spec(for selectedModelName: String) -> KieModelSpec? {
        let apiName = ModelProvider.apiModelName(from: selectedModelName)
        return specs.first { $0.model.caseInsensitiveCompare(apiName) == .orderedSame }
    }
}
