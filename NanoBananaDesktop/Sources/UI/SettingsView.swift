import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.localized("settings.title"))
                    .font(.largeTitle.weight(.semibold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localized("settings.group.api"))
                            .font(.headline)

                        LabeledContent(viewModel.localized("settings.api_key")) {
                            SecureField("", text: Binding(
                                get: { viewModel.config.apiKey },
                                set: { viewModel.config.apiKey = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

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

                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.localized("settings.prompt_enhancement_instruction"))
                                .font(.callout)

                            TextEditor(text: Binding(
                                get: { viewModel.config.promptEnhancementInstruction },
                                set: { viewModel.config.promptEnhancementInstruction = $0 }
                            ))
                            .font(.callout)
                            .frame(minHeight: 88)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.localized("settings.prompt_from_image_instruction"))
                                .font(.callout)

                            TextEditor(text: Binding(
                                get: { viewModel.config.promptFromImageInstruction },
                                set: { viewModel.config.promptFromImageInstruction = $0 }
                            ))
                            .font(.callout)
                            .frame(minHeight: 88)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                        }

                        Text(viewModel.localized("settings.model_sync_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    }
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
                }

                HStack {
                    Button(viewModel.localized("action.save_settings")) {
                        viewModel.saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .onAppear {
            if viewModel.availableTextModels.isEmpty && !viewModel.isLoadingModels {
                viewModel.refreshAvailableModels(trigger: .onAppear)
            }
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
}
