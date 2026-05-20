import AppKit
import SwiftUI

final class NanoBananaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}

@main
struct NanoBananaDesktopApp: App {
    @NSApplicationDelegateAdaptor(NanoBananaAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = MainViewModel(
        generationNotificationService: GenerationNotificationService()
    )

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .environment(\.locale, Locale(identifier: viewModel.config.language.localeIdentifier))
                .frame(minWidth: 980, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
