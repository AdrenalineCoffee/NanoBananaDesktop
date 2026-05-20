import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    let isVisible: Bool
    @State private var presetForEdit: PromptPreset?
    @State private var presetEditNameDraft: String = ""
    @State private var presetEditPromptDraft: String = ""
    @State private var isEditPresetSheetPresented: Bool = false
    @State private var presetForDelete: PromptPreset?
    @State private var isDeletePresetConfirmationPresented: Bool = false
    @State private var isPromptEnhancementInstructionExpanded: Bool = false
    @State private var isPromptFromImageInstructionExpanded: Bool = false
    @State private var isConceptPromptAdditionsExpanded: Bool = false
    @State private var isPresetsExpanded: Bool = false

    private var noProxyHostsTextBinding: Binding<String> {
        Binding(
            get: { viewModel.config.noProxyHosts.joined(separator: ",") },
            set: { rawValue in
                viewModel.config.noProxyHosts = rawValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    init(viewModel: MainViewModel, isVisible: Bool = true) {
        self.viewModel = viewModel
        self.isVisible = isVisible
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.localized("settings.title"))
                    .font(.largeTitle.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localized("settings.group.api"))
                            .font(.headline)

                        providerSecureKeyRow(
                            title: viewModel.localized("settings.api_key"),
                            isEnabled: Binding(
                                get: { viewModel.config.geminiEnabled },
                                set: { viewModel.config.geminiEnabled = $0 }
                            ),
                            key: Binding(
                                get: { viewModel.config.apiKey },
                                set: { viewModel.config.apiKey = $0 }
                            )
                        )

                        providerSecureKeyRow(
                            title: viewModel.localized("settings.openai_api_key"),
                            isEnabled: Binding(
                                get: { viewModel.config.openAIEnabled },
                                set: { viewModel.config.openAIEnabled = $0 }
                            ),
                            key: Binding(
                                get: { viewModel.config.openAIAPIKey },
                                set: { viewModel.config.openAIAPIKey = $0 }
                            )
                        )

                        providerSecureKeyRow(
                            title: viewModel.localized("settings.openai_compatible_api_key"),
                            isEnabled: Binding(
                                get: { viewModel.config.openAICompatibleEnabled },
                                set: { viewModel.config.openAICompatibleEnabled = $0 }
                            ),
                            key: Binding(
                                get: { viewModel.config.openAICompatibleAPIKey },
                                set: { viewModel.config.openAICompatibleAPIKey = $0 }
                            )
                        )

                        LabeledContent(viewModel.localized("settings.openai_compatible_base_url")) {
                            TextField(AppConfig.defaultOpenAICompatibleBaseURL, text: Binding(
                                get: { viewModel.config.openAICompatibleBaseURL },
                                set: { viewModel.config.openAICompatibleBaseURL = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        providerSecureKeyRow(
                            title: viewModel.localized("settings.kie_api_key"),
                            isEnabled: Binding(
                                get: { viewModel.config.kieEnabled },
                                set: { viewModel.config.kieEnabled = $0 }
                            ),
                            key: Binding(
                                get: { viewModel.config.kieAPIKey },
                                set: { viewModel.config.kieAPIKey = $0 }
                            )
                        )

                        LabeledContent(viewModel.localized("settings.image_model")) {
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
                            .frame(width: 320, alignment: .trailing)
                        }

                        LabeledContent(viewModel.localized("settings.prompt_model")) {
                            Picker("", selection: Binding(
                                get: { viewModel.config.promptEnhancementModel },
                                set: { viewModel.config.promptEnhancementModel = $0 }
                            )) {
                                ForEach(viewModel.selectableTextModels) { model in
                                    Text(viewModel.modelTitle(for: model)).tag(model.name)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 320, alignment: .trailing)
                        }

                        HStack(spacing: 10) {
                            Text(viewModel.localized("settings.text_models_status"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if viewModel.isLoadingModels {
                                ProgressView()
                                    .scaleEffect(0.75)
                            }

                            Text(textModelsStatusText)
                                .font(.caption)
                                .foregroundStyle(textModelsStatusColor)

                            Button {
                                viewModel.refreshAvailableModels(trigger: .manual)
                            } label: {
                                Label(viewModel.localized("settings.refresh_models"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isLoadingModels)
                        }

                        HStack(spacing: 10) {
                            Button {
                                viewModel.checkAPIAvailability()
                            } label: {
                                Label(
                                    viewModel.localized("settings.api_check"),
                                    systemImage: "network.badge.shield.half.filled"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isCheckingAPIAvailability)

                            if viewModel.isCheckingAPIAvailability {
                                ProgressView()
                                    .scaleEffect(0.75)
                                Text(viewModel.localized("settings.api_check_in_progress"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        if let apiAvailabilityMessage = viewModel.apiAvailabilityMessage,
                           !apiAvailabilityMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(apiAvailabilityMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.apiAvailabilityMessageIsError ? .red : .green)
                        }

                        collapsibleEditorSection(
                            title: viewModel.localized("settings.prompt_enhancement_instruction"),
                            isExpanded: $isPromptEnhancementInstructionExpanded,
                            text: Binding(
                                get: { viewModel.config.promptEnhancementInstruction },
                                set: { viewModel.config.promptEnhancementInstruction = $0 }
                            )
                        )

                        collapsibleEditorSection(
                            title: viewModel.localized("settings.prompt_from_image_instruction"),
                            isExpanded: $isPromptFromImageInstructionExpanded,
                            text: Binding(
                                get: { viewModel.config.promptFromImageInstruction },
                                set: { viewModel.config.promptFromImageInstruction = $0 }
                            )
                        )

                        collapsibleEditorSection(
                            title: viewModel.localized("settings.concept_prompt_additions"),
                            isExpanded: $isConceptPromptAdditionsExpanded,
                            text: Binding(
                                get: { viewModel.config.conceptPromptAdditions },
                                set: { viewModel.config.conceptPromptAdditions = $0 }
                            )
                        )

                        Text(viewModel.localized("settings.model_sync_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        collapsiblePresetsSection
                    }
                    .padding(12)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localized("settings.group.proxy"))
                            .font(.headline)

                        Toggle(viewModel.localized("settings.proxy_enabled"), isOn: Binding(
                            get: { viewModel.config.proxyEnabled },
                            set: { viewModel.config.proxyEnabled = $0 }
                        ))

                        Toggle(viewModel.localized("settings.allow_direct_fallback"), isOn: Binding(
                            get: { viewModel.config.allowDirectFallback },
                            set: { viewModel.config.allowDirectFallback = $0 }
                        ))

                        if viewModel.config.proxyEnabled {
                            LabeledContent(viewModel.localized("settings.proxy_type")) {
                                Picker("", selection: Binding(
                                    get: { viewModel.config.proxyType },
                                    set: { viewModel.config.proxyType = $0 }
                                )) {
                                    ForEach(ProxyType.allCases) { type in
                                        Text(viewModel.localized(type.titleKey)).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            LabeledContent(viewModel.localized("settings.proxy_host")) {
                                TextField("proxy.example.com", text: Binding(
                                    get: { viewModel.config.proxyHost },
                                    set: { viewModel.config.proxyHost = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent(viewModel.localized("settings.proxy_port")) {
                                TextField("8080", value: Binding(
                                    get: { viewModel.config.proxyPort },
                                    set: { viewModel.config.proxyPort = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                            }

                            LabeledContent(viewModel.localized("settings.proxy_username")) {
                                TextField("", text: Binding(
                                    get: { viewModel.config.proxyUsername },
                                    set: { viewModel.config.proxyUsername = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent(viewModel.localized("settings.proxy_password")) {
                                SecureField("", text: Binding(
                                    get: { viewModel.config.proxyPassword },
                                    set: { viewModel.config.proxyPassword = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent(viewModel.localized("settings.no_proxy_hosts")) {
                                TextField("localhost,127.0.0.1", text: noProxyHostsTextBinding)
                                    .textFieldStyle(.roundedBorder)
                            }

                            if let validationError = viewModel.proxyValidationResult.error {
                                Text(viewModel.localized(validationError.localizationKey))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Text(viewModel.localized("settings.proxy_storage_warning"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localized("settings.group.output"))
                            .font(.headline)

                        LabeledContent(viewModel.localized("settings.output_dir")) {
                            HStack {
                                TextField(viewModel.localized("settings.output_dir_placeholder"), text: Binding(
                                    get: { viewModel.config.defaultOutputDir },
                                    set: { viewModel.config.defaultOutputDir = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)

                                Button(viewModel.localized("action.browse")) {
                                    openOutputDirectoryPanel()
                                }
                            }
                        }

                        Text(viewModel.localized("settings.output_default_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LabeledContent(viewModel.localized("settings.timeout")) {
                            Stepper(value: Binding(
                                get: { viewModel.config.requestTimeoutSec },
                                set: { viewModel.config.requestTimeoutSec = $0 }
                            ), in: 10...600, step: 5) {
                                Text("\(viewModel.config.requestTimeoutSec) sec")
                            }
                            .frame(maxWidth: 180, alignment: .trailing)
                        }

                        Toggle(viewModel.localized("settings.generation_completion_notifications"), isOn: Binding(
                            get: { viewModel.config.generationCompletionNotificationsEnabled },
                            set: { viewModel.config.generationCompletionNotificationsEnabled = $0 }
                        ))
                    }
                    .padding(12)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localized("settings.group.localization"))
                            .font(.headline)

                        LabeledContent(viewModel.localized("settings.language")) {
                            Picker("", selection: Binding(
                                get: { viewModel.config.language },
                                set: { viewModel.setLanguage($0) }
                            )) {
                                Text("Русский").tag(AppLanguage.ru)
                                Text("English").tag(AppLanguage.en)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                    }
                    .padding(12)
                }

                HStack {
                    Button(viewModel.localized("action.save_settings")) {
                        viewModel.saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    Spacer()
                    Text(viewModel.localized("settings.version_value", appVersionDisplay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .onAppear {
            if isVisible && viewModel.availableTextModels.isEmpty && !viewModel.isLoadingModels {
                viewModel.refreshAvailableModels(trigger: .onAppear)
            }
        }
        .onChange(of: isVisible) { newValue in
            if newValue && viewModel.availableTextModels.isEmpty && !viewModel.isLoadingModels {
                viewModel.refreshAvailableModels(trigger: .onAppear)
            }
        }
        .sheet(isPresented: $isEditPresetSheetPresented) {
            editPresetSheet
        }
        .confirmationDialog(
            viewModel.localized("settings.preset_delete_confirm_title"),
            isPresented: $isDeletePresetConfirmationPresented,
            presenting: presetForDelete
        ) { preset in
            Button(viewModel.localized("settings.preset_delete"), role: .destructive) {
                viewModel.deletePreset(id: preset.id)
                presetForDelete = nil
            }
            Button(viewModel.localized("action.cancel"), role: .cancel) {
                presetForDelete = nil
            }
        } message: { preset in
            Text(viewModel.localized("settings.preset_delete_confirm_message", preset.name))
        }
    }

    private func openOutputDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setOutputDirectory(path: url.path)
        }
    }

    private var textModelsStatusText: String {
        if viewModel.isLoadingModels {
            return viewModel.localized("settings.text_models_loading")
        }

        if let errorMessage = viewModel.modelCatalogErrorMessage,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return errorMessage
        }

        if viewModel.availableTextModels.isEmpty {
            return viewModel.localized("settings.text_models_not_loaded")
        }

        return viewModel.localized("settings.text_models_loaded", viewModel.availableTextModels.count)
    }

    private var textModelsStatusColor: Color {
        if viewModel.isLoadingModels {
            return .secondary
        }

        if let errorMessage = viewModel.modelCatalogErrorMessage,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }

        if viewModel.availableTextModels.isEmpty {
            return .secondary
        }

        return .green
    }

    @ViewBuilder
    private func providerSecureKeyRow(
        title: String,
        isEnabled: Binding<Bool>,
        key: Binding<String>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Toggle(viewModel.localized("settings.provider_enabled"), isOn: isEnabled)
                    .toggleStyle(.switch)

                SecureField("", text: key)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEnabled.wrappedValue)
            }
        }
    }

    @ViewBuilder
    private func collapsibleEditorSection(
        title: String,
        isExpanded: Binding<Bool>,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                TextEditor(text: text)
                    .font(.callout)
                    .frame(minHeight: 112)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var collapsiblePresetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isPresetsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(viewModel.localized("settings.group.presets"))
                        .font(.callout)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isPresetsExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPresetsExpanded {
                if viewModel.sortedPromptPresets.isEmpty {
                    Text(viewModel.localized("settings.presets_empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sortedPromptPresets) { preset in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name)
                                        .font(.callout.weight(.semibold))
                                    Text(viewModel.presetMetadataText(for: preset))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(preset.prompt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }

                                Spacer(minLength: 8)

                                Button {
                                    presetForEdit = preset
                                    presetEditNameDraft = preset.name
                                    presetEditPromptDraft = preset.prompt
                                    isEditPresetSheetPresented = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .help(viewModel.localized("settings.preset_edit"))

                                Button(role: .destructive) {
                                    presetForDelete = preset
                                    isDeletePresetConfirmationPresented = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .help(viewModel.localized("settings.preset_delete"))
                            }
                            .padding(.vertical, 4)

                            if preset.id != viewModel.sortedPromptPresets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var appVersionDisplay: String {
        let rawVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBuild = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let version = (rawVersion?.isEmpty == false) ? rawVersion : nil
        let build = (rawBuild?.isEmpty == false) ? rawBuild : nil

        switch (version, build) {
        case let (.some(version), .some(build)):
            return version == build ? version : "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        case (.none, .none):
            return "dev"
        }
    }

    private var editPresetSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.localized("settings.preset_edit_title"))
                .font(.title3.weight(.semibold))

            TextField(
                viewModel.localized("settings.preset_name_placeholder"),
                text: $presetEditNameDraft
            )
            .textFieldStyle(.roundedBorder)

            Text(viewModel.localized("settings.preset_prompt"))
                .font(.callout.weight(.medium))

            TextEditor(text: $presetEditPromptDraft)
                .font(.callout)
                .frame(minHeight: 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Spacer()
                Button(viewModel.localized("action.cancel")) {
                    isEditPresetSheetPresented = false
                    presetForEdit = nil
                }
                .keyboardShortcut(.cancelAction)

                Button(viewModel.localized("settings.preset_edit")) {
                    guard let presetForEdit else {
                        isEditPresetSheetPresented = false
                        return
                    }
                    viewModel.updatePreset(
                        id: presetForEdit.id,
                        newName: presetEditNameDraft,
                        newPrompt: presetEditPromptDraft
                    )
                    isEditPresetSheetPresented = false
                    self.presetForEdit = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}
