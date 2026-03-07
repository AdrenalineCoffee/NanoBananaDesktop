import AppKit
import SwiftUI

struct ImagePreviewLayout {
    static func rows(for imageCount: Int) -> [[Int]] {
        let boundedCount = min(max(imageCount, 0), 4)
        switch boundedCount {
        case 0:
            return []
        case 1:
            return [[0]]
        case 2:
            return [[0, 1]]
        case 3:
            return [[0, 1], [2]]
        default:
            return [[0, 1], [2, 3]]
        }
    }
}

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var fullscreenImage: NSImage?
    @State private var promptDropTarget: PromptDropTarget?

    private let inspectorMinWidth: CGFloat = 460
    private let inspectorMaxWidth: CGFloat = 560
    private let panelCornerRadius: CGFloat = 14
    private let dividerColor = Color.black.opacity(0.42)

    var body: some View {
        ZStack {
            mainBackground
                .ignoresSafeArea()

            GeometryReader { geometry in
                let inspectorWidth = computedInspectorWidth(totalWidth: geometry.size.width)

                VStack(spacing: 0) {
                    headerBar

                    HStack(spacing: 0) {
                        canvasPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        darkVerticalDivider

                        inspectorPane
                            .frame(width: inspectorWidth)
                            .frame(maxHeight: .infinity)
                    }
                }
                .background(.ultraThinMaterial)
            }
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
            viewModel.handleMainViewAppeared()
        }
        .sheet(isPresented: $viewModel.isPresetNameSheetPresented) {
            presetNameSheet
        }
        .alert(
            viewModel.localized("main.preset_overwrite_title"),
            isPresented: $viewModel.isPresetOverwriteAlertPresented
        ) {
            Button(viewModel.localized("action.cancel"), role: .cancel) {
                viewModel.cancelPresetOverwrite()
            }
            Button(viewModel.localized("action.replace"), role: .destructive) {
                viewModel.confirmPresetOverwrite()
            }
        } message: {
            Text(
                viewModel.localized(
                    "main.preset_overwrite_message",
                    viewModel.pendingPresetOverwriteName ?? ""
                )
            )
        }
    }

    private var mainBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.11),
                Color(red: 0.09, green: 0.10, blue: 0.14),
                Color(red: 0.05, green: 0.06, blue: 0.09)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerBar: some View {
        HStack {
            Text(viewModel.localized("main.title"))
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))

            Spacer()

            proxyStatusPill
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .bottom) {
            darkHorizontalDivider
        }
    }

    private var proxyStatusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.proxyStatusSymbol)
            Text(viewModel.localized(viewModel.proxyStatusKey))
            Text(viewModel.proxySummary)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var canvasPane: some View {
        VStack(spacing: 14) {
            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            outputPanel
        }
        .padding(16)
    }

    private var darkHorizontalDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
    }

    private var darkVerticalDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(width: 1)
    }

    private var canvasContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            if !viewModel.lastGeneratedImages.isEmpty {
                previewGrid(images: viewModel.lastGeneratedImages)
                .padding(18)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text(viewModel.localized("main.canvas_empty_title"))
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(viewModel.localized("main.canvas_empty_description"))
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func previewGrid(images: [NSImage]) -> some View {
        GeometryReader { geometry in
            let rows = ImagePreviewLayout.rows(for: images.count)
            let rowSpacing: CGFloat = 8
            let columnSpacing: CGFloat = 8
            let rowCount = max(rows.count, 1)
            let contentHeight = max(0, geometry.size.height - rowSpacing * CGFloat(max(rowCount - 1, 0)))
            let rowHeight = contentHeight / CGFloat(rowCount)
            let twoColumnWidth = max(0, (geometry.size.width - columnSpacing) / 2)

            VStack(spacing: rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: columnSpacing) {
                        if row.count == 1, images.count > 1 {
                            Spacer(minLength: 0)
                        }

                        ForEach(row, id: \.self) { index in
                            let width = cardWidth(
                                totalImageCount: images.count,
                                rowImageCount: row.count,
                                availableWidth: geometry.size.width,
                                twoColumnWidth: twoColumnWidth
                            )
                            previewCard(
                                image: images[index],
                                width: width,
                                height: rowHeight
                            )
                        }

                        if row.count == 1, images.count > 1 {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func previewCard(image: NSImage, width: CGFloat, height: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .padding(10)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                fullscreenImage = image
            }
    }

    private func cardWidth(
        totalImageCount: Int,
        rowImageCount: Int,
        availableWidth: CGFloat,
        twoColumnWidth: CGFloat
    ) -> CGFloat {
        if totalImageCount == 1 {
            return max(0, availableWidth)
        }
        if rowImageCount == 1 {
            return twoColumnWidth
        }
        return twoColumnWidth
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(viewModel.localized("main.last_output"), systemImage: "photo.badge.checkmark")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            if !viewModel.lastOutputPaths.isEmpty {
                ForEach(viewModel.lastOutputPaths, id: \.self) { outputPath in
                    Text(outputPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button(viewModel.localized("action.show_in_finder")) {
                    viewModel.revealLastOutputInFinder()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(viewModel.localized("main.last_output_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var inspectorPane: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    if let startupWarning = viewModel.startupWarning {
                        messageBox(startupWarning, color: .orange)
                    }

                    promptSection
                    imageSettingsSection

                    if let successMessage = viewModel.successMessage {
                        messageBox(successMessage, color: .green)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        messageBox(errorMessage, color: .red)
                    }

                    if let modelResponseText = viewModel.modelResponseText,
                       !modelResponseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.localized("main.model_response"))
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.92))

                            Text(modelResponseText)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.88))
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                                .fill(Color.black.opacity(0.24))
                                .overlay(
                                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(16)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(spacing: 8) {
                if viewModel.isGenerating {
                    ProgressView()
                        .scaleEffect(0.9)
                }

                Button {
                    viewModel.generate()
                } label: {
                    Text(viewModel.isGenerating ? viewModel.localized("action.generating") : viewModel.localized("action.generate"))
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.blue)
                .disabled(!viewModel.canGenerate)
            }
            .padding(16)
            .background(Color.black.opacity(0.24))
        }
        .background(Color.black.opacity(0.18))
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.localized("main.prompt"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))

            ZStack(alignment: .topLeading) {
                PromptTextEditor(
                    text: $viewModel.prompt,
                    mentionToInsert: $viewModel.pendingMentionInsert,
                    onFilesDropped: { urls, target in
                        switch target {
                        case .attachments:
                            viewModel.handleDroppedImageURLs(urls)
                        case .convertToPrompt:
                            viewModel.generatePromptFromImage(from: urls)
                        }
                    },
                    onDropTargetChanged: { target in
                        promptDropTarget = target
                    }
                )
                .frame(minHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(0.85), lineWidth: 1.4)
                )
                .allowsHitTesting(!viewModel.isGeneratingPromptFromImage)

                if viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(viewModel.localized("main.prompt_drop_hint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                if promptDropTarget != nil {
                    promptConvertOverlay
                }

                if viewModel.isGeneratingPromptFromImage {
                    promptLoadingOverlay
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        promptSavePresetFloatingButton
                    }
                }
                .padding(10)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.enhancePrompt()
                } label: {
                    Label(
                        viewModel.isEnhancingPrompt ? viewModel.localized("action.enhancing_prompt") : viewModel.localized("action.enhance_prompt"),
                        systemImage: "slider.horizontal.below.rectangle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canEnhancePrompt)

                if viewModel.isEnhancingPrompt {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Spacer(minLength: 8)

                Menu {
                    if viewModel.sortedPromptPresets.isEmpty {
                        Text(viewModel.localized("main.presets_empty"))
                    } else {
                        ForEach(viewModel.sortedPromptPresets) { preset in
                            Button {
                                viewModel.applyPreset(id: preset.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                    Text(viewModel.presetMetadataText(for: preset))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } label: {
                    Label(viewModel.presetsMenuTitle, systemImage: "square.stack.3d.up")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
            }

            attachmentStrip
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onChange(of: viewModel.isGeneratingPromptFromImage) { isGenerating in
            if !isGenerating {
                promptDropTarget = nil
            }
        }
    }

    private var imageSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isImageSettingsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(viewModel.localized("main.image_settings"))
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Image(systemName: viewModel.isImageSettingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white.opacity(0.94))
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.isImageSettingsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.localized("main.model"))
                            .font(.title3.weight(.medium))

                        HStack(spacing: 8) {
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
                            .frame(maxWidth: .infinity)

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
                        } else if viewModel.isLoadingModels {
                            Text(viewModel.localized("main.model_loading"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(viewModel.localized("main.resolution"))
                                .font(.title3.weight(.medium))
                            Spacer()
                            Text(viewModel.resolutionValueLabel)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.90))
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.resolutionSliderValue },
                                set: { viewModel.resolutionSliderValue = $0 }
                            ),
                            in: 0...2,
                            step: 1
                        )
                        .tint(.blue)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(viewModel.localized("main.aspect_ratio"))
                                .font(.title3.weight(.medium))
                            Spacer()
                            Text(aspectRatioValueText)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.90))
                        }

                        Slider(value: aspectRatioSliderBinding, in: 0...Double(aspectRatioOptions.count - 1), step: 1)
                            .tint(.blue)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(viewModel.localized("main.image_count"))
                                .font(.title3.weight(.medium))
                            Spacer()
                            Text(viewModel.imageCountValueLabel)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.90))
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.imageCountSliderValue },
                                set: { viewModel.imageCountSliderValue = $0 }
                            ),
                            in: 1...4,
                            step: 1
                        )
                        .tint(.blue)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !viewModel.attachedImages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.localized("attachments.title"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 4) {
            if let thumbnail = attachment.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 84, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 84, height: 64)
                    .overlay(Image(systemName: "photo"))
            }

            Text(attachment.displayName)
                .lineLimit(1)
                .font(.caption2)
            Text(attachment.mentionToken)
                .lineLimit(1)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(width: 96, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                viewModel.removeAttachment(id: attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .padding(3)
            .help(viewModel.localized("attachments.remove"))
        }
        .onTapGesture {
            viewModel.requestMentionInsert(for: attachment)
        }
        .help(viewModel.localized("attachments.insert_mention"))
    }

    private func computedInspectorWidth(totalWidth: CGFloat) -> CGFloat {
        let preferred = totalWidth * 0.34
        let clamped = min(max(preferred, inspectorMinWidth), inspectorMaxWidth)
        return min(clamped, totalWidth * 0.48)
    }

    private var aspectRatioOptions: [AspectRatioSelection] {
        AspectRatioSelection.allCases
    }

    private var aspectRatioSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(aspectRatioOptions.firstIndex(of: viewModel.aspectRatioSelection) ?? 0)
            },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                let clamped = min(max(rounded, 0), max(0, aspectRatioOptions.count - 1))
                viewModel.aspectRatioSelection = aspectRatioOptions[clamped]
            }
        )
    }

    private var aspectRatioValueText: String {
        if viewModel.aspectRatioSelection == .auto {
            return viewModel.localized("main.aspect_ratio_auto_short")
        }

        return viewModel.aspectRatioSelection.manualAspectRatio?.rawValue ?? ImageAspectRatio.square.rawValue
    }

    @ViewBuilder
    private func messageBox(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    @ViewBuilder
    private var promptConvertOverlay: some View {
        GeometryReader { geometry in
            let zoneHeight = max(86, geometry.size.height * 0.30)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.localized("main.prompt_convert_zone"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(viewModel.localized("main.prompt_convert_zone_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    promptDropTarget == .convertToPrompt ? Color.blue.opacity(0.9) : Color.white.opacity(0.25),
                                    lineWidth: promptDropTarget == .convertToPrompt ? 1.8 : 1.0
                                )
                        )
                )
                .padding(8)
                .frame(height: zoneHeight, alignment: .bottom)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var promptLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text(viewModel.localized("status.prompt_from_image_in_progress"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
        }
        .allowsHitTesting(true)
    }

    private var promptSavePresetFloatingButton: some View {
        Button {
            viewModel.presentSavePresetSheet()
        } label: {
            Text("+")
                .font(.title3.weight(.bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(viewModel.canSavePromptPreset ? 0.96 : 0.52))
        .background(
            Circle()
                .fill(viewModel.canSavePromptPreset ? Color.blue.opacity(0.90) : Color.white.opacity(0.12))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
        .disabled(!viewModel.canSavePromptPreset)
        .help(viewModel.localized("action.save_preset"))
    }

    private var presetNameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.localized("main.save_preset_sheet_title"))
                .font(.title3.weight(.semibold))

            Text(viewModel.localized("main.save_preset_sheet_hint"))
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField(
                viewModel.localized("main.save_preset_name_placeholder"),
                text: $viewModel.presetNameDraft
            )
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Spacer()
                Button(viewModel.localized("action.cancel")) {
                    viewModel.cancelPresetSaveFlow()
                }
                .keyboardShortcut(.cancelAction)

                Button(viewModel.localized("action.save_preset")) {
                    viewModel.commitPresetFromDraft()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
