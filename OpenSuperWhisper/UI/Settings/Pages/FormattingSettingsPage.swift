import SwiftUI

struct FormattingSettingsPage: View {
    @ObservedObject private var vm = SettingsViewModel.shared

    var body: some View {
        SettingsPageScroll {
            autoFormatSection
            SettingsOnDeviceSection()
            apiSection
            SettingsMemorySection()
            SettingsFormatTestSection()
        }
    }

    private var autoFormatSection: some View {
        DLSection("AI auto format") {
            DLToggleRow(
                title: "Format with AI",
                subtitle: "After transcription, a language model fixes grammar and formatting before the text is saved and pasted.",
                isOn: $vm.formattingEnabled
            )
            DLDivider()
            HStack(spacing: 12) {
                ForEach(FormattingBackend.allCases) { backend in
                    SettingsChoiceCard(
                        title: backend.title,
                        subtitle: backend.subtitle,
                        selected: vm.formattingBackend == backend,
                        action: { vm.formattingBackend = backend }
                    ) {
                        IconWell(systemName: backend == .api ? "globe" : "lock.shield", size: 30)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .opacity(vm.formattingEnabled ? 1 : 0.6)
        }
    }

    private var apiSection: some View {
        DLSection(
            "API endpoint",
            note: vm.formattingBackend == .api ? nil : "used when API endpoint is selected"
        ) {
            DLRow(
                title: "Base URL",
                subtitle: "Any OpenAI-compatible endpoint: OpenAI, OpenRouter, Groq, Ollama (http://localhost:11434/v1), LM Studio…"
            ) {
                DLTextField(placeholder: "https://api.openai.com/v1", text: $vm.llmBaseURL, mono: true)
                    .frame(width: 270)
            }
            DLDivider()
            DLRow(title: "API key", subtitle: "Leave empty for local servers that don’t need one.") {
                DLTextField(placeholder: "sk-...", text: $vm.llmApiKey, mono: true, secure: true)
                    .frame(width: 270)
            }
            DLDivider()
            DLRow(title: "Model", subtitle: modelCaption) {
                HStack(spacing: 8) {
                    DLTextField(placeholder: "gpt-4o-mini", text: $vm.llmModel, mono: true)
                        .frame(width: 170)
                    if !vm.availableLLMModels.isEmpty {
                        DLMenuPicker(
                            selection: $vm.llmModel,
                            items: vm.availableLLMModels.map { (value: $0, label: $0) },
                            width: 150
                        )
                    }
                    Button {
                        vm.fetchLLMModels()
                    } label: {
                        Label(vm.isFetchingLLMModels ? "Fetching…" : "Fetch models", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.dl(.secondary, size: .small))
                    .disabled(vm.isFetchingLLMModels)
                    .help("List models from the configured endpoint")
                }
            }
            if let error = vm.llmModelsFetchError {
                Text(error)
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.live)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modelCaption: String {
        if vm.llmModelsFetchError != nil { return "Couldn’t list models from this endpoint." }
        if !vm.availableLLMModels.isEmpty { return "\(vm.availableLLMModels.count) models available from this endpoint." }
        return "Type a model id, or fetch the endpoint’s model list and pick from it."
    }
}

// MARK: - On-device S1-mini

struct SettingsOnDeviceSection: View {
    @ObservedObject private var vm = SettingsViewModel.shared
    @ObservedObject private var s1 = S1MiniModelManager.shared
    @State private var confirmingDelete = false

    private var variant: S1MiniModelManager.Variant {
        S1MiniModelManager.Variant.all.first { $0.id == vm.s1MiniVariant } ?? .fourBit
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    var body: some View {
        _ = s1.installedRevision
        let installed = s1.isInstalled(variant)
        return DLSection(
            "On-device · S1-mini",
            note: vm.formattingBackend == .s1mini ? nil : "used when On-device is selected"
        ) {
            DLRow(title: "Model weights") {
                weightsAction(installed: installed)
            }
            weightsStatus(installed: installed)
                .padding(.horizontal, 16)
                .padding(.top, -8)
                .padding(.bottom, 12)

            DLDivider()
            DLRow(title: "Quantization", subtitle: "8-bit is larger (≈\(bytes(S1MiniModelManager.Variant.eightBit.approximateBytes))) with no measured gain.") {
                DLSegmented(
                    selection: $vm.s1MiniVariant,
                    options: [(value: "4bit", label: "4-bit (recommended)"), (value: "8bit", label: "8-bit")],
                    size: .small
                )
                .disabled(s1.isDownloading)
            }

            DLDivider()
            styleBlock

            DLDivider()
            SettingsFootnote(text: "English only. S1-mini normalizes rather than rewrites — use the API backend for modes that need a real prompt.")
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
        }
        .confirmationDialog("Delete the S1-mini \(variant.id) weights?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { s1.delete(variant) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees \(bytes(s1.installedBytes(variant))). On-device formatting stops working until you download them again.")
        }
    }

    @ViewBuilder
    private func weightsStatus(installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if s1.isDownloading {
                DLLinearProgress(progress: s1.downloadProgress).frame(maxWidth: 320)
                Text("\(s1.downloadingFile.isEmpty ? "Starting" : s1.downloadingFile) — \(Int(s1.downloadProgress * 100))%")
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
            } else if installed {
                (Text("Installed — \(bytes(s1.installedBytes(variant)))").foregroundStyle(DL.ok).fontWeight(.semibold)
                 + Text(" · \(variant.id)").foregroundStyle(DL.sub))
                    .font(DL.text(11.5))
            } else {
                Text("Not downloaded — ≈\(bytes(variant.approximateBytes))")
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
            }
            if let error = s1.lastError {
                Text(error).font(DL.text(11.5)).foregroundStyle(DL.live).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func weightsAction(installed: Bool) -> some View {
        if s1.isDownloading {
            Button("Cancel") { s1.cancelDownload() }
                .buttonStyle(.dl(.secondary, size: .small))
        } else if installed {
            Button {
                confirmingDelete = true
            } label: {
                Label("Delete…", systemImage: "trash")
            }
            .buttonStyle(.dl(.dangerSoft, size: .small))
        } else {
            Button {
                s1.download(variant)
            } label: {
                Label("Download", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.dl(.primary, size: .small))
        }
    }

    private var styleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Default style").font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                Text("S1-mini’s prompt is fixed by its training — these three settings are how you steer it. Modes can override them per app.")
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsStyleLine(label: "Styling", detail: vm.s1DefaultStyling.detail) {
                DLSegmented(selection: $vm.s1DefaultStyling, options: S1Styling.allCases.map { (value: $0, label: $0.title) }, size: .small)
            }
            SettingsStyleLine(label: "Structure", detail: vm.s1DefaultStructure.detail) {
                DLSegmented(selection: $vm.s1DefaultStructure, options: S1Structure.allCases.map { (value: $0, label: $0.title) }, size: .small)
            }
            SettingsStyleLine(label: "Context", detail: vm.s1DefaultContext.detail) {
                DLSegmented(selection: $vm.s1DefaultContext, options: S1Context.allCases.map { (value: $0, label: $0.title) }, size: .small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// "Styling  [segmented]  description".
struct SettingsStyleLine<Control: View>: View {
    let label: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(DL.text(12.5))
                .foregroundStyle(DL.sub)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                control()
                Text(detail).font(DL.text(11)).foregroundStyle(DL.faint)
            }
        }
    }
}
