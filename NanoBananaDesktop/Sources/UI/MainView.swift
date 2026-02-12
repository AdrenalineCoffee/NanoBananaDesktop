import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showFullscreenImage = false
    private let controlsCardHeight: CGFloat = 220

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(viewModel.localized("main.title"))
                        .font(.largeTitle.weight(.semibold))

                    if let startupWarning = viewModel.startupWarning {
                        messageBox(startupWarning, color: .orange)
                    }

                    card(title: viewModel.localized("main.prompt"), systemImage: "text.quote") {
                        ZStack(alignment: .topLeading) {
                            PromptTextEditor(
                                text: $viewModel.prompt,
                                mentionToInsert: $viewModel.pendingMentionInsert,
                                onFilesDropped: viewModel.handleDroppedImageURLs
                            )
                            .frame(minHeight: 190)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
                            )

                            if viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(viewModel.localized("main.prompt_drop_hint"))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                viewModel.enhancePrompt()
                            } label: {
                                Label(
                                    viewModel.isEnhancingPrompt
                                        ? viewModel.localized("action.enhancing_prompt")
                                        : viewModel.localized("action.enhance_prompt"),
                                    systemImage: "text.badge.star"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                viewModel.isEnhancingPrompt ||
                                viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )

                            if viewModel.isEnhancingPrompt {
                                ProgressView()
                                    .scaleEffect(0.75)
                            }
                        }

                        attachmentStrip
                    }

                    card(
                        title: viewModel.localized("main.image_settings"),
                        systemImage: "slider.horizontal.3",
                        minHeight: controlsCardHeight
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(viewModel.localized("main.model"))
                                        .foregroundStyle(.secondary)
                                    Spacer()

                                    if viewModel.isLoadingModels {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                    }

                                    Picker("", selection: Binding(
                                        get: { viewModel.config.model },
                                        set: { viewModel.config.model = $0 }
                                    )) {
                                        ForEach(viewModel.selectableImageModels) { model in
                                            Text(viewModel.modelTitle(for: model)).tag(model.name)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 250, alignment: .trailing)

                                    Button {
                                        viewModel.refreshAvailableModels(trigger: .manual)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(viewModel.isLoadingModels)
                                    .help(viewModel.localized("main.model_refresh"))
                                }

                                if let modelCatalogErrorMessage = viewModel.modelCatalogErrorMessage,
                                   !modelCatalogErrorMessage.isEmpty {
                                    Text(modelCatalogErrorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else if viewModel.isLoadingModels {
                                    Text(viewModel.localized("main.model_loading"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Divider()

                            HStack(spacing: 10) {
                                Text(viewModel.localized("main.resolution"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("", selection: $viewModel.resolutionSelection) {
                                    Text("1K").tag(ResolutionSelection.k1)
                                    Text("2K").tag(ResolutionSelection.k2)
                                    Text("4K").tag(ResolutionSelection.k4)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 120, alignment: .trailing)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(viewModel.localized("main.aspect_ratio"))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Picker("", selection: $viewModel.aspectRatioSelection) {
                                        ForEach(AspectRatioSelection.allCases) { selection in
                                            Text(aspectRatioTitle(for: selection)).tag(selection)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 170, alignment: .trailing)
                                }

                                if viewModel.aspectRatioSelection == .auto {
                                    Text(viewModel.aspectRatioAutoDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            viewModel.generate()
                        } label: {
                            Label(
                                viewModel.isGenerating ? viewModel.localized("action.generating") : viewModel.localized("action.generate"),
                                systemImage: "wand.and.stars"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(!viewModel.canGenerate)
                        .buttonStyle(.borderedProminent)
                    }

                    if viewModel.isGenerating {
                        ProgressView()
                    }

                    if let generatedImage = viewModel.lastGeneratedImage {
                        card(title: viewModel.localized("main.generated_preview"), systemImage: "photo") {
                            Image(nsImage: generatedImage)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onTapGesture {
                                    showFullscreenImage = true
                                }

                            Text(viewModel.localized("main.fullscreen_hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let successMessage = viewModel.successMessage {
                        messageBox(successMessage, color: .green)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        messageBox(errorMessage, color: .red)
                    }

                    if let outputPath = viewModel.lastOutputPath {
                        card(title: viewModel.localized("main.last_output"), systemImage: "photo.stack") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(outputPath)
                                    .textSelection(.enabled)
                                    .font(.caption.monospaced())
                                Button(viewModel.localized("action.show_in_finder")) {
                                    viewModel.revealLastOutputInFinder()
                                }
                            }
                        }
                    }

                    if let modelResponseText = viewModel.modelResponseText,
                       !modelResponseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        card(title: viewModel.localized("main.model_response"), systemImage: "text.bubble") {
                            Text(modelResponseText)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(24)
            }
            .allowsHitTesting(!showFullscreenImage)

            if showFullscreenImage, let generatedImage = viewModel.lastGeneratedImage {
                GeneratedImageFullscreenView(
                    image: generatedImage,
                    closeHint: viewModel.localized("main.fullscreen_hint"),
                    onClose: { showFullscreenImage = false }
                )
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.handleMainViewAppeared()
        }
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.localized("attachments.title"))
                .font(.subheadline.weight(.medium))

            if viewModel.attachedImages.isEmpty {
                Text(viewModel.localized("attachments.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.attachedImages) { attachment in
                            attachmentCard(attachment)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentCard(_ attachment: AttachedImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thumbnail = attachment.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 110, height: 80)
                    .overlay(Image(systemName: "photo"))
            }

            Text(attachment.displayName)
                .lineLimit(1)
                .font(.caption)
            Text(attachment.mentionToken)
                .lineLimit(1)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: 128, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                viewModel.removeAttachment(id: attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help(viewModel.localized("attachments.remove"))
            .padding(4)
        }
        .onTapGesture {
            viewModel.requestMentionInsert(for: attachment)
        }
        .help(viewModel.localized("attachments.insert_mention"))
    }

    private func aspectRatioTitle(for selection: AspectRatioSelection) -> String {
        if selection == .auto {
            return viewModel.localized("main.aspect_ratio_auto")
        }
        return selection.manualAspectRatio?.rawValue ?? ImageAspectRatio.square.rawValue
    }

    @ViewBuilder
    private func card<Content: View>(
        title: String,
        systemImage: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func messageBox(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
