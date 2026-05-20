import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConceptingView: View {
    @ObservedObject var appViewModel: MainViewModel
    @ObservedObject var viewModel: ConceptingViewModel
    let isVisible: Bool

    @State private var draggedLayerID: UUID?
    @State private var isCanvasSectionExpanded: Bool = true
    @State private var editingLayerID: UUID?
    @State private var editingLayerName: String = ""
    @FocusState private var focusedLayerID: UUID?

    private let headerBarHeight: CGFloat = 52
    private let dividerColor = Color.black.opacity(0.42)
    private let borderColor = Color.white.opacity(0.14)
    private let swatchColors: [ConceptRGBAColor] = [
        .clear,
        .white,
        .black,
        .blue,
        ConceptRGBAColor(red: 0.90, green: 0.30, blue: 0.24, alpha: 1),
        ConceptRGBAColor(red: 0.18, green: 0.78, blue: 0.44, alpha: 1),
        ConceptRGBAColor(red: 0.98, green: 0.81, blue: 0.24, alpha: 1)
    ]

    var body: some View {
        GeometryReader { geometry in
            let paneMetrics = paneMetrics(for: geometry.size.width)

            ZStack {
                mainBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    HStack(spacing: 0) {
                        layersPane
                            .frame(width: paneMetrics.left)

                        darkVerticalDivider

                        canvasPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        darkVerticalDivider

                        inspectorPane
                            .frame(width: paneMetrics.right)
                    }
                }
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            guard isVisible else { return }
            viewModel.loadIfNeeded(defaultModel: appViewModel.config.model)
            appViewModel.refreshAvailableModels(trigger: .onAppear)
        }
        .onChange(of: isVisible) { newValue in
            guard newValue else { return }
            viewModel.loadIfNeeded(defaultModel: appViewModel.config.model)
            appViewModel.refreshAvailableModels(trigger: .onAppear)
        }
    }

    private func paneMetrics(for totalWidth: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let left = min(max(totalWidth * 0.23, 228), 272)
        let right = min(max(totalWidth * 0.31, 320), 392)
        return (left, right)
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
        ZStack {
            Text(appViewModel.localized("concept.title"))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Button {
                    viewModel.createNewProject(defaultModel: appViewModel.config.model)
                } label: {
                    Text(appViewModel.localized("concept.new"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Spacer()
                if appViewModel.config.proxyEnabled {
                    proxyStatusPill
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: headerBarHeight)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .bottom) {
            darkHorizontalDivider
        }
    }

    private var proxyStatusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: appViewModel.proxyStatusSymbol)
            Text(appViewModel.localized(appViewModel.proxyStatusKey))
            Text(appViewModel.proxySummary)
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
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private var layersPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                layersHeader
                layersList
                darkHorizontalDivider
                canvasSettingsSection
            }
            .padding(18)
        }
        .background(Color.black.opacity(0.12))
    }

    private var layersHeader: some View {
        HStack {
            Text(appViewModel.localized("concept.layers"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))

            Spacer()

            toolbarIconButton(systemName: "plus") {
                viewModel.addSketchLayer()
            }
            .help(appViewModel.localized("concept.add_layer"))

            toolbarIconButton(systemName: "photo.on.rectangle.angled") {
                openImageImportPanel()
            }
            .help(appViewModel.localized("concept.import_image"))

            toolbarIconButton(systemName: "photo.badge.plus") {
                viewModel.addReferenceLayer()
            }
            .help(appViewModel.localized("concept.add_reference"))
        }
    }

    private var layersList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.layers) { layer in
                layerRow(layer)
                    .onDrag {
                        draggedLayerID = layer.id
                        return NSItemProvider(object: layer.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: ConceptLayerDropDelegate(
                            targetLayerID: layer.id,
                            draggedLayerID: $draggedLayerID,
                            viewModel: viewModel
                        )
                    )
            }
        }
    }

    private var canvasSettingsSection: some View {
        DisclosureGroup(
            isExpanded: $isCanvasSectionExpanded,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    conceptFieldLabel("concept.canvas_aspect")
                    Picker("", selection: Binding(
                        get: { viewModel.project?.canvasAspectRatio ?? .landscape16x9 },
                        set: { viewModel.setCanvasAspectRatio($0) }
                    )) {
                        ForEach(ImageAspectRatio.allCases) { aspectRatio in
                            Text(aspectRatio.rawValue).tag(aspectRatio)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    conceptFieldLabel("concept.canvas_background")
                    HStack(spacing: 10) {
                        ForEach(swatchColors, id: \.self) { color in
                            Button {
                                viewModel.setCanvasBackgroundColor(color)
                            } label: {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                color == (viewModel.project?.canvasBackgroundColor ?? .white)
                                                    ? Color.white.opacity(0.9)
                                                    : Color.white.opacity(0.18),
                                                lineWidth: color == (viewModel.project?.canvasBackgroundColor ?? .white) ? 2 : 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 10)
            },
            label: {
                disclosureLabel("concept.canvas")
            }
        )
        .tint(.white.opacity(0.86))
    }

    private func layerRow(_ layer: ConceptLayer) -> some View {
        let isSelected = viewModel.selectedLayerID == layer.id

        return HStack(spacing: 10) {
            Button {
                viewModel.toggleVisibility(for: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.toggleLock(for: layer.id)
            } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                if editingLayerID == layer.id {
                    TextField(
                        "",
                        text: Binding(
                            get: { editingLayerName },
                            set: { editingLayerName = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .focused($focusedLayerID, equals: layer.id)
                    .onSubmit {
                        commitLayerEditing(for: layer.id)
                    }
                    .onExitCommand {
                        cancelLayerEditing()
                    }
                } else {
                    Text(layer.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            beginLayerEditing(layer)
                        }
                }

                Text(layerTypeLabel(for: layer.type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if viewModel.removingBackgroundLayerID == layer.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .help(appViewModel.localized("concept.remove_background"))
                } else {
                    layerRowIconButton(
                        systemName: "person.crop.rectangle",
                        helpKey: "concept.remove_background",
                        isDisabled: viewModel.removingBackgroundLayerID != nil || !viewModel.layerHasRenderableContent(layer.id)
                    ) {
                        viewModel.removeBackground(from: layer.id)
                    }
                }
                layerRowIconButton(systemName: "square.on.square", helpKey: "concept.duplicate_layer") {
                    viewModel.duplicateLayer(layer.id)
                }
                layerRowIconButton(systemName: "trash", helpKey: "concept.delete_layer") {
                    viewModel.deleteLayer(layer.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.14) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            viewModel.selectLayer(layer.id)
        }
        .onChange(of: focusedLayerID) { newValue in
            if editingLayerID == layer.id, newValue != layer.id {
                commitLayerEditing(for: layer.id)
            }
        }
    }

    private var canvasPane: some View {
        ZStack(alignment: .top) {
            ConceptCanvasView(
                viewModel: viewModel,
                emptyTitle: appViewModel.localized("concept.canvas_empty_title"),
                emptyDescription: appViewModel.localized("concept.canvas_empty_description")
            )
            .padding(18)

            canvasToolbar
                .padding(.top, 16)
        }
        .background(Color.black.opacity(0.12))
    }

    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            toolPillButton(.brush, systemName: "paintbrush")
            toolPillButton(.eraser, systemName: "eraser")
            toolPillButton(.fill, systemName: "paint.bucket.classic")

            toolbarDivider

            HStack(spacing: 8) {
                ForEach(swatchColors.filter { $0.alpha > 0.001 }, id: \.self) { color in
                    Button {
                        viewModel.setBrushColor(color)
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(
                                        color == viewModel.brushColor ? Color.white.opacity(0.9) : Color.white.opacity(0.18),
                                        lineWidth: color == viewModel.brushColor ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            toolbarDivider

            HStack(spacing: 8) {
                Text(appViewModel.localized("concept.brush_size"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { viewModel.brushWidth },
                        set: { viewModel.setBrushWidth($0) }
                    ),
                    in: 1...64
                )
                .frame(width: 120)
                Text("\(Int(viewModel.brushWidth.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 32, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text(appViewModel.localized("concept.opacity"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { viewModel.brushOpacity },
                        set: { viewModel.setBrushOpacity($0) }
                    ),
                    in: 0.05...1
                )
                .frame(width: 92)
            }

            toolbarDivider

            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canUndo || !isVisible)
            .keyboardShortcut("z", modifiers: [.command])

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRedo || !isVisible)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            toolbarDivider

            Button {
                viewModel.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)

            Button {
                viewModel.resetZoom()
            } label: {
                Text("\(Int((viewModel.zoomScale * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.86))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.36))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 20)
    }

    private var inspectorPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    promptSection

                    if let errorMessage = viewModel.errorMessage {
                        messageBanner(text: errorMessage, isError: true)
                    }

                    if let successMessage = viewModel.successMessage {
                        messageBanner(text: successMessage, isError: false)
                    }

                    darkHorizontalDivider

                    settingsSection
                }
                .padding(18)
            }

            darkHorizontalDivider

            Button {
                viewModel.generate(using: appViewModel)
            } label: {
                HStack {
                    if viewModel.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isGenerating ? appViewModel.localized("action.generating") : appViewModel.localized("action.generate"))
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.96))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(viewModel.canGenerate ? 0.85 : 0.35))
            )
            .disabled(!viewModel.canGenerate)
            .padding(18)
        }
        .background(Color.black.opacity(0.12))
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appViewModel.localized("main.prompt"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { viewModel.project?.prompt ?? "" },
                    set: { viewModel.setPrompt($0) }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white.opacity(0.95))
                .padding(10)
                .frame(minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        )
                )

                if (viewModel.project?.prompt ?? "").isEmpty {
                    Text(appViewModel.localized("concept.prompt_placeholder"))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.leading, 18)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }

            if !combinedPromptPreview.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appViewModel.localized("concept.final_prompt_preview"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(combinedPromptPreview)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.82))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        )
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appViewModel.localized("main.image_settings"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            darkHorizontalDivider
                .padding(.top, 12)
                .padding(.bottom, 16)

            conceptDisclosureBlock(title: "main.model") {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { normalizedConceptModel },
                        set: { viewModel.setModel($0) }
                    )) {
                        ForEach(conceptSelectableModels, id: \.id) { item in
                            Text(appViewModel.modelTitle(for: item)).tag(item.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Button {
                        appViewModel.refreshAvailableModels(trigger: .manual)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(borderColor, lineWidth: 1)
                            )
                    )
                }
            }

            conceptDisclosureBlock(title: "concept.reference_mode") {
                segmentedRow(
                    items: [
                        (appViewModel.localized("concept.reference_mode.strict"), ConceptReferenceMode.strictPreserve),
                        (appViewModel.localized("concept.reference_mode.balanced"), ConceptReferenceMode.balanced),
                        (appViewModel.localized("concept.reference_mode.creative"), ConceptReferenceMode.creative)
                    ],
                    selected: viewModel.project?.referenceMode ?? .balanced
                ) { mode in
                    viewModel.setReferenceMode(mode)
                }
            }

            conceptDisclosureBlock(title: "main.resolution") {
                segmentedRow(
                    items: [
                        (ImageResolution.k1.rawValue, ResolutionSelection.k1),
                        (ImageResolution.k2.rawValue, ResolutionSelection.k2),
                        (ImageResolution.k4.rawValue, ResolutionSelection.k4)
                    ],
                    selected: viewModel.project?.resolutionSelection ?? .k1
                ) { selection in
                    viewModel.setResolutionSelection(selection)
                }
            }

            conceptDisclosureBlock(title: "main.image_count", includeBottomDivider: false) {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.project?.imageCount ?? 1) },
                            set: { viewModel.setImageCount(Int($0.rounded())) }
                        ),
                        in: 1...4,
                        step: 1
                    )

                    Text("\(viewModel.project?.imageCount ?? 1)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 42, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        )
                }
            }
        }
    }

    private var conceptSelectableModels: [ModelCatalogItem] {
        let currentModel = normalizedConceptModel
        let baseModels = appViewModel.selectableImageModels.filter { item in
            guard item.provider == .kie else { return true }
            return KieModelRegistry.spec(for: item.name)?.supportsConcepting == true
        }
        if baseModels.contains(where: { $0.name == currentModel }) {
            return baseModels
        }
        let currentProvider = ModelProvider.inferImageProvider(from: currentModel)
        if currentProvider == .kie,
           KieModelRegistry.spec(for: currentModel)?.supportsConcepting != true {
            return baseModels
        }
        guard appViewModel.isProviderEnabled(currentProvider) else {
            return baseModels
        }
        return [
            ModelCatalogItem(
                provider: currentProvider,
                name: currentModel,
                displayName: currentModel,
                description: "",
                supportedMethods: ["generateContent"],
                isCustomFallback: true
            )
        ] + baseModels
    }

    private var normalizedConceptModel: String {
        let trimmed = viewModel.project?.model.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AppConfig.defaultModel : trimmed
    }

    private var combinedPromptPreview: String {
        viewModel.combinedUserPromptPreview(promptAdditions: appViewModel.config.conceptPromptAdditions)
    }

    private func disclosureLabel(_ key: String) -> some View {
        HStack {
            Text(appViewModel.localized(key))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func conceptDisclosureBlock<Content: View>(
        title key: String,
        includeBottomDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            disclosureLabel(key)
            content()
            if includeBottomDivider {
                darkHorizontalDivider
            }
        }
        .padding(.bottom, includeBottomDivider ? 16 : 0)
    }

    private func conceptFieldLabel(_ key: String) -> some View {
        Text(appViewModel.localized(key))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func toolbarIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func smallActionButton(_ systemName: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(appViewModel.localized(key))
    }

    private func layerRowIconButton(
        systemName: String,
        helpKey: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDisabled ? .white.opacity(0.28) : .white.opacity(0.72))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(appViewModel.localized(helpKey))
    }

    private func toolPillButton(_ tool: ConceptTool, systemName: String) -> some View {
        Button {
            viewModel.activeTool = tool
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewModel.activeTool == tool ? Color.white : Color.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(viewModel.activeTool == tool ? Color.blue.opacity(0.62) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func segmentedRow<T: Equatable>(
        items: [(String, T)],
        selected: T,
        action: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    action(item.1)
                } label: {
                    Text(item.0)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selected == item.1 ? Color.white.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < items.count - 1 {
                    segmentedMiniDivider
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private func segmentedMiniButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var segmentedMiniDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 24)
    }

    private func messageBanner(text: String, isError: Bool) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isError ? Color.red.opacity(0.92) : Color.green.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
            )
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

    private func layerTypeLabel(for type: ConceptLayerType) -> String {
        switch type {
        case .referenceImage:
            return appViewModel.localized("concept.layer_type.reference")
        case .sketch:
            return appViewModel.localized("concept.layer_type.sketch")
        case .result:
            return appViewModel.localized("concept.layer_type.result")
        }
    }

    private func openImageImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            viewModel.importReferenceImage(from: url)
        }
    }

    private func beginLayerEditing(_ layer: ConceptLayer) {
        editingLayerID = layer.id
        editingLayerName = layer.name
        focusedLayerID = layer.id
    }

    private func commitLayerEditing(for layerID: UUID) {
        let trimmed = editingLayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            viewModel.setLayerName(trimmed, for: layerID)
        }
        cancelLayerEditing()
    }

    private func cancelLayerEditing() {
        editingLayerID = nil
        editingLayerName = ""
        focusedLayerID = nil
    }
}

private struct ConceptLayerDropDelegate: DropDelegate {
    let targetLayerID: UUID
    @Binding var draggedLayerID: UUID?
    let viewModel: ConceptingViewModel

    func dropEntered(info: DropInfo) {
        guard let draggedLayerID, draggedLayerID != targetLayerID else { return }
        guard let targetIndex = viewModel.layers.firstIndex(where: { $0.id == targetLayerID }) else { return }
        viewModel.moveLayer(draggedLayerID, to: targetIndex)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.finalizeLayerReorder()
        draggedLayerID = nil
        return true
    }
}
