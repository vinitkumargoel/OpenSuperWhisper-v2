import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ModesSettingsPage: View {
    @ObservedObject private var vm = SettingsViewModel.shared
    @State private var confirmingDeleteModeID: String?

    var body: some View {
        SettingsPageScroll {
            modesSection
            SettingsVocabularySection()
        }
        .onAppear {
            if vm.editingModeBinding() == nil {
                vm.editingModeID = vm.activeFormattingModeID.isEmpty
                    ? (vm.formattingModes.first?.id.uuidString ?? "")
                    : vm.activeFormattingModeID
            }
        }
    }

    private func modeName(_ mode: FormattingMode) -> String {
        mode.name.isEmpty ? "Untitled" : mode.name
    }

    private var modesSection: some View {
        DLSection("Formatting modes", trailing: {
            Button {
                vm.addFormattingMode()
            } label: {
                Label("Add mode", systemImage: "plus")
            }
            .buttonStyle(.dl(.secondary, size: .small))
        }) {
            DLToggleRow(
                title: "Auto-switch by active app",
                subtitle: "Uses the mode whose app list matches the app that was in front when recording started. Otherwise the active mode is used.",
                isOn: $vm.autoSwitchFormattingMode
            )
            DLDivider()
            DLRow(title: "Active mode", subtitle: vm.autoSwitchFormattingMode ? "Used for apps that no mode claims" : "Used for every recording") {
                DLMenuPicker(
                    selection: $vm.activeFormattingModeID,
                    items: vm.formattingModes.map { (value: $0.id.uuidString, label: modeName($0)) },
                    width: 170
                )
            }
            DLDivider()
            VStack(alignment: .leading, spacing: 14) {
                modeChips
                if let mode = vm.editingModeBinding() {
                    SettingsModeEditor(mode: mode)
                    HStack {
                        Button {
                            mode.wrappedValue.prompt = AppPreferences.defaultFormattingPrompt
                        } label: {
                            Label("Restore default prompt", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.dl(.ghost, size: .small))
                        .disabled(mode.wrappedValue.prompt == AppPreferences.defaultFormattingPrompt)
                        Spacer()
                        Button {
                            confirmingDeleteModeID = mode.wrappedValue.id.uuidString
                        } label: {
                            Label("Delete mode…", systemImage: "trash")
                        }
                        .buttonStyle(.dl(.dangerSoft, size: .small))
                        .disabled(vm.formattingModes.count <= 1)
                    }
                }
            }
            .padding(16)
        }
        .confirmationDialog(
            "Delete this mode?",
            isPresented: Binding(get: { confirmingDeleteModeID != nil }, set: { if !$0 { confirmingDeleteModeID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Mode", role: .destructive) {
                if let id = confirmingDeleteModeID { vm.deleteFormattingMode(id) }
                confirmingDeleteModeID = nil
            }
            Button("Cancel", role: .cancel) { confirmingDeleteModeID = nil }
        } message: {
            Text("Its prompt, style and app list are removed. Apps it claimed fall back to the active mode.")
        }
    }

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.formattingModes) { mode in
                    SettingsModeChip(
                        name: modeName(mode),
                        appCount: mode.appBundleIDs.count,
                        isActive: mode.id.uuidString == vm.activeFormattingModeID,
                        isEditing: mode.id.uuidString == vm.editingModeID
                    ) {
                        vm.editingModeID = mode.id.uuidString
                    }
                }
            }
        }
    }
}

private struct SettingsModeChip: View {
    let name: String
    let appCount: Int
    let isActive: Bool
    let isEditing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isActive { Circle().fill(DL.ok).frame(width: 7, height: 7) }
                Text(name).font(DL.text(12.5, .semibold))
                if appCount > 0 {
                    Text(appCount == 1 ? "1 app" : "\(appCount) apps")
                        .font(DL.mono(10.5, .regular))
                        .foregroundStyle(isEditing ? Color.white.opacity(0.65) : DL.faint)
                }
            }
            .foregroundStyle(isEditing ? Color.white : DL.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(isEditing ? DL.ink : DL.card))
            .overlay(Capsule().strokeBorder(isEditing ? Color.clear : DL.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Name, apps, on-device style and prompt of one mode.
private struct SettingsModeEditor: View {
    @Binding var mode: FormattingMode
    @State private var typedBundleID = ""
    @ObservedObject private var vm = SettingsViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormLine(label: "Name") {
                DLTextField(placeholder: "Mode name", text: $mode.name)
                    .frame(maxWidth: 260)
            }
            SettingsFormLine(label: "Auto-activate for") {
                SettingsFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(mode.appBundleIDs, id: \.self) { bundleID in
                        SettingsAppToken(bundleID: bundleID) {
                            mode.appBundleIDs.removeAll { $0 == bundleID }
                        }
                    }
                    Button {
                        pickApp()
                    } label: {
                        Label("Add app…", systemImage: "plus")
                    }
                    .buttonStyle(.dl(.ghost, size: .small))
                }
                TextField("or type a bundle ID, e.g. com.tinyspeck.slackmacgap", text: $typedBundleID)
                    .onSubmit(addTypedID)
                    .dlField(mono: true)
                    .frame(maxWidth: 380)
                Text("Pick apps from a list — bundle IDs are filled in for you. Used only when auto-switch is on.")
                    .font(DL.text(11))
                    .foregroundStyle(DL.faint)
            }
            SettingsFormLine(label: "On-device style", caption: "Default inherits the Formatting page") {
                styleControl(\.styling, all: S1Styling.allCases, title: \.title, fallback: vm.s1DefaultStyling.title)
                styleControl(\.structure, all: S1Structure.allCases, title: \.title, fallback: vm.s1DefaultStructure.title)
                styleControl(\.context, all: S1Context.allCases, title: \.title, fallback: vm.s1DefaultContext.title)
                Text("S1-mini can’t read the prompt below — these are its only controls.")
                    .font(DL.text(11))
                    .foregroundStyle(DL.faint)
            }
            SettingsFormLine(label: "Prompt", caption: "API backend") {
                DLTextEditor(text: $mode.prompt, mono: true, minHeight: 110)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.well.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.line2, lineWidth: 1))
    }

    /// Segmented control whose first option, "Default", clears the override.
    private func styleControl<Axis: Hashable>(
        _ keyPath: WritableKeyPath<FormattingMode, Axis?>,
        all: [Axis],
        title: KeyPath<Axis, String>,
        fallback: String
    ) -> some View {
        DLSegmented(
            selection: Binding(get: { mode[keyPath: keyPath] }, set: { mode[keyPath: keyPath] = $0 }),
            options: [(value: Axis?.none, label: "Default (\(fallback))")] + all.map { (value: Optional($0), label: $0[keyPath: title]) },
            size: .small
        )
    }

    private func addTypedID() {
        let ids = typedBundleID
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !mode.appBundleIDs.contains($0) }
        mode.appBundleIDs.append(contentsOf: ids)
        typedBundleID = ""
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose the apps that should use this mode"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !mode.appBundleIDs.contains(id) {
                mode.appBundleIDs.append(id)
            }
        }
    }
}

/// App icon + name + bundle id, with a remove button.
private struct SettingsAppToken: View {
    let bundleID: String
    let onRemove: () -> Void

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    private var name: String? {
        appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 12)).foregroundStyle(DL.faint)
            }
            if let name {
                Text(name).font(DL.text(12, .semibold)).foregroundStyle(DL.ink)
            }
            Text(bundleID).font(DL.mono(10.5, .regular)).foregroundStyle(DL.faint).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DL.faint)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DL.card))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }
}

// MARK: - Vocabulary

struct SettingsVocabularySection: View {
    @ObservedObject private var vm = SettingsViewModel.shared

    var body: some View {
        DLSection("Custom vocabulary", trailing: {
            Button {
                vm.addVocabularyRule()
            } label: {
                Label("Add word", systemImage: "plus")
            }
            .buttonStyle(.dl(.secondary, size: .small))
        }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Fix names, jargon and acronyms the model mishears. Applied after every transcription — even with AI formatting off.")
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if vm.vocabularyRules.isEmpty {
                    Text("No replacements yet. Add one to correct terms like “clod code” → “Claude Code”.")
                        .font(DL.text(12))
                        .foregroundStyle(DL.faint)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                } else {
                    header
                    ForEach($vm.vocabularyRules) { $rule in
                        DLDivider()
                        HStack(spacing: 10) {
                            DLTextField(placeholder: "clod code", text: $rule.from)
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(DL.faint)
                            DLTextField(placeholder: "Claude Code", text: $rule.to)
                            DLCheckbox(isOn: $rule.caseSensitive)
                                .help("Case-sensitive match")
                                .frame(width: 36)
                            Button {
                                vm.deleteVocabularyRule(rule.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.dlIcon(size: 26, bordered: false))
                            .help("Remove this replacement")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("HEARD").frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: 10)
            Text("REPLACE WITH").frame(maxWidth: .infinity, alignment: .leading)
            Text("Aa").frame(width: 36)
            Spacer().frame(width: 26)
        }
        .font(DL.text(10, .semibold))
        .tracking(0.6)
        .foregroundStyle(DL.faint)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
