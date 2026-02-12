import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: MainViewModel

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
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

                                statusBadge(for: item.status)
                                routeBadge(for: item.networkRoute)
                            }

                            Text(item.prompt)
                                .lineLimit(2)

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
                            }

                            if let error = item.errorMessage, !error.isEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
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
           let outputPath = item.outputImagePath,
           let image = NSImage(contentsOfFile: outputPath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
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

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
