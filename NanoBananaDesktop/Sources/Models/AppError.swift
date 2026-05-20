import Foundation

enum AppError: Error, Equatable {
    case emptyPrompt
    case missingAPIKey
    case missingOpenAIAPIKey
    case missingOpenAICompatibleAPIKey
    case missingKieAPIKey
    case providerDisabled(String)
    case invalidOpenAICompatibleBaseURL(String)
    case promptFromImageNoValidFile
    case promptFromImageModelNotSupported(String)
    case missingInputImage
    case unreadableInputImage
    case unsupportedAttachmentFormat(String)
    case unreadableAttachment(String)
    case invalidOutputDirectory
    case invalidConfiguration(String)
    case modelCatalogUnavailable(String)
    case noImageReadyModels
    case noTextReadyModels

    case proxyNotConfigured
    case proxyConnectionFailed(String)
    case proxyAuthFailed(String)
    case directFallbackDisabled(String)
    case proxyInvalidSettings(String)

    case network(String)
    case timeout
    case timeoutWithDetails(String)
    case unauthorized
    case permissionDenied
    case quotaExceeded
    case billingCreditsDepleted(String)
    case rateLimited
    case serverError(Int)
    case invalidResponse
    case noImageInResponse
    case noTextInResponse
    case decodingError
    case ioError(String)
    case kieUploadFailed(String)
    case kieTaskFailed(String)
    case conceptNoEditableRegion
    case conceptNoLockedBase
    case conceptNoProjectLoaded
    case conceptInvalidLayer
    case conceptImportFailed(String)
    case conceptBackgroundRemovalUnavailable
    case conceptBackgroundRemovalFailed(String)

    var localizationKey: String {
        switch self {
        case .emptyPrompt:
            return "error.empty_prompt"
        case .missingAPIKey:
            return "error.missing_api_key"
        case .missingOpenAIAPIKey:
            return "error.missing_openai_api_key"
        case .missingOpenAICompatibleAPIKey:
            return "error.missing_openai_compatible_api_key"
        case .missingKieAPIKey:
            return "error.missing_kie_api_key"
        case .providerDisabled:
            return "error.provider_disabled"
        case .invalidOpenAICompatibleBaseURL:
            return "error.invalid_openai_compatible_base_url"
        case .promptFromImageNoValidFile:
            return "error.prompt_from_image_no_valid_file"
        case .promptFromImageModelNotSupported:
            return "error.prompt_from_image_model_not_supported"
        case .missingInputImage:
            return "error.missing_input_image"
        case .unreadableInputImage:
            return "error.unreadable_input_image"
        case .unsupportedAttachmentFormat:
            return "error.unsupported_attachment_format"
        case .unreadableAttachment:
            return "error.unreadable_attachment"
        case .invalidOutputDirectory:
            return "error.invalid_output_directory"
        case .invalidConfiguration:
            return "error.invalid_configuration"
        case .modelCatalogUnavailable:
            return "error.model_catalog_unavailable"
        case .noImageReadyModels:
            return "error.no_image_ready_models"
        case .noTextReadyModels:
            return "error.no_text_ready_models"
        case .proxyNotConfigured:
            return "error.proxy_not_configured"
        case .proxyConnectionFailed:
            return "error.proxy_connection_failed"
        case .proxyAuthFailed:
            return "error.proxy_auth_failed"
        case .directFallbackDisabled:
            return "error.direct_fallback_disabled"
        case .proxyInvalidSettings:
            return "error.proxy_invalid_settings"
        case .network:
            return "error.network"
        case .timeout:
            return "error.timeout"
        case .timeoutWithDetails:
            return "error.timeout"
        case .unauthorized:
            return "error.unauthorized"
        case .permissionDenied:
            return "error.permission_denied"
        case .quotaExceeded:
            return "error.quota"
        case .billingCreditsDepleted:
            return "error.billing_credits_depleted"
        case .rateLimited:
            return "error.rate_limited"
        case .serverError:
            return "error.server"
        case .invalidResponse:
            return "error.invalid_response"
        case .noImageInResponse:
            return "error.no_image"
        case .noTextInResponse:
            return "error.no_text_in_response"
        case .decodingError:
            return "error.decoding"
        case .ioError:
            return "error.io"
        case .kieUploadFailed:
            return "error.kie_upload_failed"
        case .kieTaskFailed:
            return "error.kie_task_failed"
        case .conceptNoEditableRegion:
            return "error.concept_no_editable_region"
        case .conceptNoLockedBase:
            return "error.concept_no_locked_base"
        case .conceptNoProjectLoaded:
            return "error.concept_no_project_loaded"
        case .conceptInvalidLayer:
            return "error.concept_invalid_layer"
        case .conceptImportFailed:
            return "error.concept_import_failed"
        case .conceptBackgroundRemovalUnavailable:
            return "error.concept_background_removal_unavailable"
        case .conceptBackgroundRemovalFailed:
            return "error.concept_background_removal_failed"
        }
    }

    var debugDetails: String {
        switch self {
        case .invalidConfiguration(let message),
             .modelCatalogUnavailable(let message),
             .network(let message),
             .ioError(let message),
             .proxyConnectionFailed(let message),
             .proxyAuthFailed(let message),
             .directFallbackDisabled(let message),
             .proxyInvalidSettings(let message),
             .providerDisabled(let message),
             .invalidOpenAICompatibleBaseURL(let message),
             .timeoutWithDetails(let message),
             .billingCreditsDepleted(let message),
             .kieUploadFailed(let message),
             .kieTaskFailed(let message),
             .conceptImportFailed(let message),
             .conceptBackgroundRemovalFailed(let message):
            return message
        case .promptFromImageModelNotSupported:
            return ""
        case .unsupportedAttachmentFormat, .unreadableAttachment:
            return ""
        case .serverError(let code):
            return "HTTP \(code)"
        default:
            return ""
        }
    }

    static func billingCreditsDepletedError(message: String?) -> AppError? {
        let rawMessage = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = rawMessage.lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        let billingMarkers = [
            "prepayment credits are depleted",
            "prepaid credits",
            "credits are depleted",
            "credit balance",
            "insufficient credits",
            "insufficient credit",
            "insufficient balance",
            "account balance",
            "balance is not enough",
            "payment required",
            "billing_hard_limit_reached",
            "manage your project and billing",
            "billing#prepay",
            "prepay",
            "billing"
        ]

        guard billingMarkers.contains(where: { normalized.contains($0) }) else {
            return nil
        }

        return .billingCreditsDepleted(rawMessage)
    }

    static func quotaError(message: String?) -> AppError? {
        let normalized = (message ?? "").lowercased()
        guard normalized.contains("quota")
            || normalized.contains("resource_exhausted")
            || normalized.contains("quota_exceeded")
            || normalized.contains("insufficient_quota")
            || normalized.contains("rate quota")
            || normalized.contains("limit exceeded") else {
            return nil
        }
        return .quotaExceeded
    }

    var isRecoverableProxyFailure: Bool {
        switch self {
        case .proxyConnectionFailed, .proxyAuthFailed:
            return true
        case .timeoutWithDetails:
            return true
        default:
            return false
        }
    }
}
