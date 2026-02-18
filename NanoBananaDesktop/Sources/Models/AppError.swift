import Foundation

enum AppError: Error, Equatable {
    case emptyPrompt
    case missingAPIKey
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
    case rateLimited
    case serverError(Int)
    case invalidResponse
    case noImageInResponse
    case noTextInResponse
    case decodingError
    case ioError(String)

    var localizationKey: String {
        switch self {
        case .emptyPrompt:
            return "error.empty_prompt"
        case .missingAPIKey:
            return "error.missing_api_key"
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
             .timeoutWithDetails(let message):
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
