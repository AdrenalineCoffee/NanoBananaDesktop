import Foundation
import UserNotifications

protocol GenerationNotificationServiceProtocol: Sendable {
    func notifyGenerationCompleted(language: AppLanguage, imageCount: Int) async
}

struct NoopGenerationNotificationService: GenerationNotificationServiceProtocol {
    func notifyGenerationCompleted(language: AppLanguage, imageCount: Int) async { }
}

actor GenerationNotificationService: GenerationNotificationServiceProtocol {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func notifyGenerationCompleted(language: AppLanguage, imageCount: Int) async {
        guard await isNotificationAuthorized() else {
            return
        }

        let normalizedCount = max(1, imageCount)
        let content = UNMutableNotificationContent()
        content.title = Localizer.string("notification.generation_completed_title", language: language)
        if normalizedCount == 1 {
            content.body = Localizer.string("notification.generation_completed_single", language: language)
        } else {
            content.body = Localizer.string("notification.generation_completed_multiple", language: language, normalizedCount)
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            notificationCenter.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private func isNotificationAuthorized() async -> Bool {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}
