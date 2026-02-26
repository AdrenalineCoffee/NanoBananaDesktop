import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: MainViewModel
    let onReuseRequested: () -> Void

    @State private var fullscreenImage: NSImage?
    @State private var localHistoryMessage: String?
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var loadingThumbnailPaths: Set<String> = []

    private let thumbnailLoader = HistoryThumbnailLoader.shared
    private let thumbnailSize = CGSize(width: 44, height: 44)

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(viewModel: MainViewModel, onReuseRequested: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onReuseRequested = onReuseRequested
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.localized("history.title"))
                    .font(.largeTitle.weight(.semibold))

                HStack(spacing: 12) {
                    Picker(viewModel.localized("history.filter"), selection: $viewModel.historyFilter) {
                        Text(viewModel.localized("history.filter.all")).tag(HistoryFilter.all)
                        Text(viewModel.localized("history.filter.success")).tag(HistoryFilter.success)
                        Text(viewModel.localized("history.filter.error")).tag(HistoryFilter.error)
                    }
                    .pickerStyle(.segmented)

                    Picker(viewModel.localized("history.route_filter"), selection: $viewModel.historyRouteFilter) {
                        Text(viewModel.localized("history.route_filter.all")).tag(HistoryRouteFilter.all)
                        Text(viewModel.localized("history.route_filter.proxy")).tag(HistoryRouteFilter.proxy)
                        Text(viewModel.localized("history.route_filter.direct")).tag(HistoryRouteFilter.directFallback)
                    }
                    .pickerStyle(.segmented)
                }

                if let localHistoryMessage, !localHistoryMessage.isEmpty {
                    Text(localHistoryMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        )
                }

                if viewModel.filteredHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(viewModel.localized("history.empty"), systemImage: "tray")
                            .font(.headline)
                        Text(viewModel.localized("history.empty_description"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    List(viewModel.filteredHistory) { item in
                        HStack(alignment: .top, spacing: 10) {
                            thumbnailView(for: item)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(Self.formatter.string(from: item.timestamp))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button {
                                        copyToPasteboard(item.prompt)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)
                                    .help(viewModel.localized("history.copy_prompt"))

                                    Button {
                                        reuseHistoryItem(item)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.plain)
                                    .help(viewModel.localized("history.reuse"))

                                    Button {
                                        openLocation(for: item)
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canOpenLocation(for: item))
                                    .help(viewModel.localized("history.open_location"))

                                    statusBadge(for: item.status)
                                    routeBadge(for: item.networkRoute)
                                }

                                Text(item.prompt)
                                    .lineLimit(2)
                                    .textSelection(.enabled)

                                Text("\(item.mode.rawValue) • \(item.resolution.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let proxySummary = item.proxySummary, item.proxyUsed {
                                    Text(proxySummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let output = item.outputImagePath {
                                    Text(output)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                if let error = item.errorMessage, !error.isEmpty {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                if let diagnostics = item.failureDiagnostics,
                                   !diagnostics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("\(viewModel.localized("history.diagnostics_label")): \(diagnostics)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button(viewModel.localized("history.copy_prompt")) {
                                copyToPasteboard(item.prompt)
                            }

                            if let modelResponse = item.modelResponseText,
                               !modelResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(viewModel.localized("history.copy_model_response")) {
                                    copyToPasteboard(modelResponse)
                                }
                            }

                            if let error = item.errorMessage,
                               !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(viewModel.localized("history.copy_error")) {
                                    copyToPasteboard(error)
                                }
                            }

                            if let diagnostics = item.failureDiagnostics,
                               !diagnostics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(viewModel.localized("history.copy_diagnostics")) {
                                    copyToPasteboard(diagnostics)
                                }
                            }

                            if let outputPath = item.outputImagePath,
                               !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(viewModel.localized("history.copy_output_path")) {
                                    copyToPasteboard(outputPath)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .padding(24)
            .allowsHitTesting(fullscreenImage == nil)

            if let fullscreenImage {
                GeneratedImageFullscreenView(
                    image: fullscreenImage,
                    closeHint: viewModel.localized("main.fullscreen_hint"),
                    onClose: { self.fullscreenImage = nil }
                )
                .zIndex(20)
                .transition(.opacity)
            }
        }
        .onAppear {
            prefetchInitialThumbnails()
        }
        .onChange(of: viewModel.historyFilter) { _ in
            prefetchInitialThumbnails()
        }
        .onChange(of: viewModel.historyRouteFilter) { _ in
            prefetchInitialThumbnails()
        }
    }

    @ViewBuilder
    private func statusBadge(for status: HistoryStatus) -> some View {
        let title = status == .success
            ? viewModel.localized("history.status.success")
            : viewModel.localized("history.status.error")

        Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((status == .success ? Color.green : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(status == .success ? .green : .red)
    }

    @ViewBuilder
    private func routeBadge(for route: NetworkRoute) -> some View {
        let isProxy = route == .proxy
        Text(isProxy ? viewModel.localized("route.proxy") : viewModel.localized("route.direct_fallback"))
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isProxy ? Color.blue : Color.orange).opacity(0.15), in: Capsule())
            .foregroundStyle(isProxy ? .blue : .orange)
    }

    @ViewBuilder
    private func thumbnailView(for item: HistoryRecord) -> some View {
        if item.status == .success,
           let outputPath = item.outputImagePath {
            Button {
                openFullscreen(for: outputPath)
            } label: {
                if let image = thumbnails[outputPath] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel(viewModel.localized("history.thumbnail_alt"))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "photo"))
                        .accessibilityLabel(viewModel.localized("history.thumbnail_alt"))
                }
            }
            .buttonStyle(.plain)
            .help(viewModel.localized("history.open_fullscreen"))
            .task(id: outputPath) {
                await loadThumbnailIfNeeded(path: outputPath)
            }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "photo"))
                .accessibilityLabel(viewModel.localized("history.thumbnail_alt"))
        }
    }

    private func reuseHistoryItem(_ item: HistoryRecord) {
        localHistoryMessage = nil
        _ = viewModel.reuseFromHistory(item)
        onReuseRequested()
    }

    private func canOpenLocation(for item: HistoryRecord) -> Bool {
        guard let outputPath = item.outputImagePath else {
            return false
        }
        return !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func openLocation(for item: HistoryRecord) {
        guard let outputPath = item.outputImagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !outputPath.isEmpty else {
            return
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            localHistoryMessage = viewModel.localized("history.output_unavailable")
            return
        }

        localHistoryMessage = nil
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    private func openFullscreen(for outputPath: String) {
        let outputURL = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: outputURL.path),
              let image = NSImage(contentsOfFile: outputURL.path) else {
            localHistoryMessage = viewModel.localized("history.output_unavailable")
            return
        }

        localHistoryMessage = nil
        fullscreenImage = image
    }

    private func prefetchInitialThumbnails() {
        let outputPaths = Array(
            viewModel.filteredHistory
                .compactMap(\.outputImagePath)
                .prefix(12)
        )
        guard !outputPaths.isEmpty else {
            return
        }

        Task {
            await thumbnailLoader.prefetch(paths: outputPaths, targetSize: thumbnailSize)
            for path in outputPaths {
                await loadThumbnailIfNeeded(path: path)
            }
        }
    }

    private func loadThumbnailIfNeeded(path: String) async {
        let shouldLoad = await MainActor.run { () -> Bool in
            guard thumbnails[path] == nil, !loadingThumbnailPaths.contains(path) else {
                return false
            }
            loadingThumbnailPaths.insert(path)
            return true
        }

        guard shouldLoad else {
            return
        }

        let image = await thumbnailLoader.thumbnail(for: path, targetSize: thumbnailSize)
        await MainActor.run {
            loadingThumbnailPaths.remove(path)
            if let image {
                thumbnails[path] = image
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
