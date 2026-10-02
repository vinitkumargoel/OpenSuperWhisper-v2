import SwiftUI

/// First-run setup in four steps: welcome & language, permissions, dictation
/// key, and a voice model.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var permissions = PermissionsManager()
    @ObservedObject private var center = ModelDownloadCenter.shared
    @Environment(\.dlAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            OnbTopBar(step: viewModel.step)

            ZStack {
                switch viewModel.step {
                case .welcome:
                    OnbWelcomeStep(viewModel: viewModel)
                case .permissions:
                    OnbPermissionsStep(permissions: permissions)
                case .shortcut:
                    OnbShortcutStep(viewModel: viewModel)
                case .model:
                    OnbModelStep(center: center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity))
            .id(viewModel.step)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.window)
        .ignoresSafeArea()
        .alert(item: $center.lastError) { error in
            Alert(
                title: Text("\(error.modelName) didn't download"),
                message: Text(error.message),
                primaryButton: .default(Text("Try Again")) { center.download(error.model) },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 14) {
            if viewModel.step != .welcome {
                Button { viewModel.back() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                }
                .buttonStyle(.dl(.ghost, size: .large))
            }
            Spacer()
            if let note = footerNote {
                Text(note).font(DL.text(12.5)).foregroundStyle(DL.faint)
            }
            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
            }
            .buttonStyle(.dl(.primary, size: .large))
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.step == .model && !viewModel.canFinish(center))
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .padding(.top, 10)
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .welcome: return "Get started"
        case .permissions, .shortcut: return "Continue"
        case .model: return "Start dictating"
        }
    }

    private var footerNote: String? {
        switch viewModel.step {
        case .permissions:
            return permissions.isAccessibilityPermissionGranted ? nil : "You can skip Accessibility and grant it later"
        case .model:
            if center.isDownloading { return "Available when the download finishes" }
            return viewModel.canFinish(center) ? nil : "Download a model to continue"
        default:
            return nil
        }
    }

    private func advance() {
        switch viewModel.step {
        case .permissions:
            // The microphone is the one permission dictation cannot do without:
            // ask for it on the way past if the user has not already.
            if !permissions.isMicrophonePermissionGranted {
                permissions.requestMicrophonePermissionOrOpenSystemPreferences()
            }
            viewModel.next()
        case .model:
            guard viewModel.canFinish(center) else { return }
            appState.hasCompletedOnboarding = true
        default:
            viewModel.next()
        }
    }
}

// MARK: - Top bar

private struct OnbTopBar: View {
    let step: OnboardingStep
    @Environment(\.dlAccent) private var accent

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? AnyShapeStyle(accent.gradient)
                              : (s.rawValue < step.rawValue ? AnyShapeStyle(accent.color.opacity(0.4)) : AnyShapeStyle(DL.line)))
                        .frame(width: s == step ? 44 : 28, height: 5)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            HStack {
                Spacer()
                Text("\(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(DL.text(12, .medium))
                    .foregroundStyle(DL.faint)
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 50)
    }
}

// MARK: - Shared pieces

/// The gradient orb with a waveform glyph and soft rings.
struct OnbOrb: View {
    var size: CGFloat = 112
    @Environment(\.dlAccent) private var accent

    var body: some View {
        ZStack {
            Circle().fill(accent.color.opacity(0.05)).frame(width: size * 1.95, height: size * 1.95)
            Circle().strokeBorder(accent.color.opacity(0.12), lineWidth: 1).frame(width: size * 1.95, height: size * 1.95)
            Circle().fill(accent.color.opacity(0.07)).frame(width: size * 1.52, height: size * 1.52)
            Circle().strokeBorder(accent.color.opacity(0.18), lineWidth: 1).frame(width: size * 1.52, height: size * 1.52)
            Circle()
                .fill(
                    RadialGradient(colors: [accent.color2.opacity(0.95), accent.color], center: UnitPoint(x: 0.35, y: 0.3),
                                   startRadius: 2, endRadius: size * 0.75)
                )
                .frame(width: size, height: size)
                .shadow(color: accent.color.opacity(0.45), radius: 18, y: 8)
            Image(systemName: "waveform")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct OnbStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(DL.display(32, .heavy))
                .foregroundStyle(DL.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(DL.text(14.5))
                .foregroundStyle(DL.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 500)
        }
    }
}

// MARK: - Step 1: welcome

private struct OnbWelcomeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            OnbOrb(size: 104)
                .frame(height: 210)
                .padding(.top, 2)
            OnbStepHeader(
                title: "Welcome to OpenSuperWhisper",
                subtitle: "Talk instead of type, in any app on your Mac. Fast, free, and private — your voice never leaves this computer."
            )
            .padding(.top, 12)

            HStack(spacing: 12) {
                OnbFeatureCard(icon: "checkmark.shield", tint: DL.ok, title: "On-device", subtitle: "No account, no cloud")
                OnbFeatureCard(icon: "character.cursor.ibeam", tint: nil, title: "Any app", subtitle: "Text lands at your cursor")
                OnbFeatureCard(icon: "bolt", tint: DL.warn, title: "About 80 ms", subtitle: "with Parakeet v2")
            }
            .padding(.top, 26)

            VStack(spacing: 0) {
                DLRow(title: "I mostly speak", subtitle: "Taken from your Mac’s language settings. Auto-detect is available too.") {
                    DLMenuPicker(
                        selection: $viewModel.selectedLanguage,
                        items: LanguageUtil.availableLanguages.map { (value: $0, label: LanguageUtil.languageNames[$0] ?? $0) },
                        width: 170
                    )
                }
                DLDivider(inset: 16)
                DLRow(
                    title: "Use Asian autocorrect",
                    subtitle: viewModel.isAsianLanguage
                        ? "Fixes spacing and punctuation for Chinese, Japanese and Korean."
                        : "Appears for Chinese, Japanese and Korean",
                    dimmed: !viewModel.isAsianLanguage
                ) {
                    DLSwitch(isOn: $viewModel.useAsianAutocorrect)
                        .disabled(!viewModel.isAsianLanguage)
                }
            }
            .dlCard(radius: 14)
            .padding(.top, 18)
        }
        .frame(width: 690)
    }
}

private struct OnbFeatureCard: View {
    let icon: String
    let tint: Color?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            IconWell(systemName: icon, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                Text(subtitle).font(DL.text(11.5)).foregroundStyle(DL.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .dlCard(radius: 14)
    }
}

// MARK: - Step 2: permissions

private struct OnbPermissionsStep: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        VStack(spacing: 0) {
            OnbStepHeader(
                title: "Two quick permissions",
                subtitle: "macOS asks you to approve these once. Nothing is recorded unless the indicator is on screen."
            )
            .padding(.top, 34)

            VStack(spacing: 12) {
                OnbPermissionCard(
                    icon: "mic",
                    tint: DL.live,
                    title: "Microphone",
                    detail: "So OpenSuperWhisper can hear you while you dictate.",
                    granted: permissions.isMicrophonePermissionGranted,
                    highlighted: !permissions.isMicrophonePermissionGranted,
                    action: { permissions.requestMicrophonePermissionOrOpenSystemPreferences() }
                )
                OnbPermissionCard(
                    icon: "keyboard",
                    tint: nil,
                    title: "Accessibility",
                    detail: "Lets your shortcut work in every app and pastes the text where your cursor is.",
                    granted: permissions.isAccessibilityPermissionGranted,
                    highlighted: permissions.isMicrophonePermissionGranted && !permissions.isAccessibilityPermissionGranted,
                    action: { permissions.openSystemPreferences(for: .accessibility) }
                )

                if !permissions.isAccessibilityPermissionGranted {
                    OnbWaitingStrip()
                        .transition(.opacity)
                }
            }
            .padding(.top, 30)
            .animation(.easeInOut(duration: 0.25), value: permissions.isAccessibilityPermissionGranted)
            .animation(.easeInOut(duration: 0.25), value: permissions.isMicrophonePermissionGranted)

            Spacer(minLength: 12)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(DL.faint)
                Text("Audio is transcribed on this Mac and stays in your Library until you delete it. Nothing is sent anywhere unless you pick an API endpoint for AI formatting.")
                    .font(DL.text(12))
                    .foregroundStyle(DL.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 690)
    }
}

private struct OnbPermissionCard: View {
    let icon: String
    let tint: Color?
    let title: String
    let detail: String
    let granted: Bool
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            IconWell(systemName: icon, tint: tint, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                Text(detail).font(DL.text(12.5)).foregroundStyle(DL.sub).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                DLStatusPill(text: "Granted", kind: .ok, icon: "checkmark.circle")
            } else {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                        Text("Grant access")
                    }
                }
                .buttonStyle(.dlPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .dlCard(radius: 16, selected: highlighted && !granted)
    }
}

private struct OnbWaitingStrip: View {
    var body: some View {
        HStack(spacing: 12) {
            DLSpinner(size: 14)
            (Text("Waiting for Accessibility… In System Settings, switch on ")
                + Text("OpenSuperWhisper").bold()
                + Text(". We’ll notice automatically."))
                .font(DL.text(12.5))
                .foregroundStyle(DL.sub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                BrandMark(size: 20)
                Text("OpenSuperWhisper").font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink)
                Capsule().fill(DL.line).frame(width: 30, height: 18)
                    .overlay(alignment: .leading) { Circle().fill(.white).padding(2).shadow(radius: 0.5) }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(DL.card))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DL.line, lineWidth: 1))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DL.well))
    }
}

// MARK: - Step 3: shortcut

private struct OnbShortcutStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.dlAccent) private var accent
    private let keyboardWidth: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            OnbStepHeader(
                title: "Pick your dictation key",
                subtitle: "Hold it to talk and release to paste. A quick tap toggles recording on and off instead."
            )
            .padding(.top, 24)

            OnbKeyboardView(selectedShortcut: viewModel.selectedShortcut, width: keyboardWidth)
                .padding(.top, 20)

            // Caption pinned under the lit key.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: keyboardWidth, height: 26)
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                    Text(viewModel.selectedShortcut == .rightOption ? "Right Option" : "Option + `")
                        .font(DL.text(12, .semibold))
                }
                .foregroundStyle(accent.color)
                .fixedSize()
                .frame(width: 140)
                .offset(x: OnbKeyboardView.highlightCenterX(for: viewModel.selectedShortcut, width: keyboardWidth) - 70, y: 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedShortcut)
            }

            HStack(spacing: 12) {
                OnbShortcutCard(
                    keys: ["Right ⌥"],
                    title: "Single modifier key",
                    recommended: true,
                    detail: "One key you rarely press on its own. Easiest to reach mid-sentence.",
                    selected: viewModel.selectedShortcut == .rightOption
                ) { viewModel.selectedShortcut = .rightOption }
                OnbShortcutCard(
                    keys: ["⌥", "`"],
                    title: "Key combination",
                    recommended: false,
                    detail: "Two keys pressed together. Choose this if you use Right ⌥ for accents.",
                    selected: viewModel.selectedShortcut == .keyCombination
                ) { viewModel.selectedShortcut = .keyCombination }
            }
            .frame(width: keyboardWidth)
            .padding(.top, 16)

            Text("You can change this any time in Settings › Shortcuts.")
                .font(DL.text(12))
                .foregroundStyle(DL.faint)
                .padding(.top, 14)
        }
    }
}

private struct OnbShortcutCard: View {
    let keys: [String]
    let title: String
    let recommended: Bool
    let detail: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    HStack(spacing: 5) {
                        ForEach(keys, id: \.self) { Keycap(text: $0, highlighted: selected, minWidth: 26, height: 24) }
                    }
                    Spacer()
                    ZStack {
                        if selected {
                            Circle().fill(accent.color).frame(width: 20, height: 20)
                            Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(DL.line, lineWidth: 1.5).frame(width: 20, height: 20)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(title).font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
                    if recommended { DLAccentTag(text: "Recommended") }
                }
                .padding(.top, 2)
                Text(detail)
                    .font(DL.text(12))
                    .foregroundStyle(DL.sub)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? accent.softer : Color.clear)
            )
            .dlCard(radius: 14, selected: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: model

private struct OnbModelStep: View {
    @ObservedObject var center: ModelDownloadCenter

    var body: some View {
        VStack(spacing: 0) {
            OnbStepHeader(
                title: "Choose a voice model",
                subtitle: "Models run entirely on your Mac. Start with the recommended one — you can add others later."
            )
            .padding(.top, 34)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                        if index > 0 { DLDivider() }
                        OnbModelRow(model: model, center: center)
                    }
                }
                .dlCard(radius: 14)
                .padding(.vertical, 4)
            }
            .frame(width: 690)
            .padding(.top, 22)
        }
        .onAppear(perform: preselectInstalledModel)
    }

    /// If what preferences point at isn't downloaded but another catalogue
    /// model is, use that one — the old onboarding pre-selected it the same way.
    private func preselectInstalledModel() {
        if let active = ModelCatalog.activeModel, center.isInstalled(active) { return }
        if let installed = ModelCatalog.all.first(where: { center.isInstalled($0) }) {
            center.activate(installed)
        }
    }
}

struct OnbModelRow: View {
    let model: SpeechModel
    @ObservedObject var center: ModelDownloadCenter
    @State private var hovering = false
    @Environment(\.dlAccent) private var accent

    private var isDownloading: Bool { center.downloadingID == model.id }
    private var installed: Bool { center.isInstalled(model) }
    private var active: Bool { center.isActive(model) }

    var body: some View {
        HStack(spacing: 14) {
            IconWell(systemName: model.engine.icon, tint: active ? nil : DL.sub, fill: active ? nil : DL.well, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name).font(DL.text(13.5, .semibold)).foregroundStyle(DL.ink)
                    if let size = sizeText { DLTag(text: size, mono: true) }
                    DLTag(text: model.languages)
                    if model.recommended { DLAccentTag(text: "Recommended") }
                }
                Text(isDownloading ? center.progressDetail(for: model) : model.detail)
                    .font(DL.text(12))
                    .foregroundStyle(DL.sub)
                    .lineLimit(1)
                if isDownloading {
                    DLLinearProgress(progress: center.progress, height: 5)
                        .frame(maxWidth: 320)
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                OnbMeterLine(label: "Speed", value: model.speed)
                OnbMeterLine(label: "Accuracy", value: model.accuracy)
            }
            .frame(width: 130)

            action.frame(minWidth: 110, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(active || isDownloading ? accent.softer : (hovering && installed ? DL.well.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if installed && !active { center.activate(model) }
        }
    }

    private var sizeText: String? {
        if let bytes = center.installedBytes(model) { return ModelCatalog.formatBytes(bytes) }
        return model.sizeText
    }

    @ViewBuilder
    private var action: some View {
        if isDownloading {
            HStack(spacing: 10) {
                DLProgressRing(progress: center.progress, size: 34)
                Button("Cancel") { center.cancel() }.buttonStyle(.dl(.secondary, size: .small))
            }
        } else if active {
            DLStatusPill(text: "Selected", kind: .ok, icon: "checkmark.circle")
        } else if installed {
            Button("Use") { center.activate(model) }.buttonStyle(.dl(.secondary, size: .small))
        } else {
            Button { center.download(model) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 10.5, weight: .semibold))
                    Text("Download")
                }
            }
            .buttonStyle(.dl(.secondary, size: .small))
            .disabled(center.isDownloading)
        }
    }
}

private struct OnbMeterLine: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(DL.text(10.5)).foregroundStyle(DL.faint).frame(width: 50, alignment: .leading)
            DotMeter(value: value)
        }
    }
}
