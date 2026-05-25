# Project Context

- `Package.swift` is the fastest entry point. The app target is the macOS executable `NanoBananaDesktop`; use `swift build` and focused `swift test --filter ...` first.
- The main app is SwiftUI. Primary UI files live in `NanoBananaDesktop/Sources/UI`; app state and generation workflows live in `NanoBananaDesktop/Sources/ViewModels`.
- User settings are stored through `AppConfig` and `AppConfigStore`. Keep new settings backward-compatible by decoding missing values from `AppConfig.defaultValue()`.
- Generation history is stored as JSON through `HistoryRecord` and `HistoryStore`. Add optional fields with default initializer values so old history files still decode.
- Image generation costs are centralized in `GenerationCostRegistry`; do not duplicate provider pricing logic in views.
- Localization uses `Localizer` and `Resources/Localizations/{en,ru}.lproj/Localizable.strings`. Add both English and Russian keys for visible UI text.
- The working tree may already contain user changes. Inspect diffs before editing touched files and avoid reverting unrelated changes.
