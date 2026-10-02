import AppKit
import SwiftUI

// MARK: - Dialogs

/// A centred confirmation card: tinted icon, title, message, Cancel / confirm.
struct ConfirmDialog<Extra: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let confirmTitle: String
    var destructive = true
    var onCancel: () -> Void
    var onConfirm: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(spacing: 14) {
            IconWell(systemName: icon, tint: tint, size: 46)
            Text(title)
                .font(DL.display(17))
                .foregroundStyle(DL.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DL.text(13))
                .foregroundStyle(DL.sub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            extra()
            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.dl(.secondary, size: .large, fullWidth: true))
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(.dl(destructive ? .danger : .primary, size: .large, fullWidth: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
        .background(DL.card)
    }
}

extension ConfirmDialog where Extra == EmptyView {
    init(icon: String, tint: Color, title: String, message: String, confirmTitle: String,
         destructive: Bool = true, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.init(icon: icon, tint: tint, title: title, message: message, confirmTitle: confirmTitle,
                  destructive: destructive, onCancel: onCancel, onConfirm: onConfirm, extra: { EmptyView() })
    }
}

/// "Delete all N recordings?", optionally keeping starred ones.
struct DeleteAllDialog: View {
    let total: Int
    let starred: Int
    let onConfirm: (_ keepStarred: Bool) -> Void
    let onCancel: () -> Void
    @State private var keepStarred = true

    var body: some View {
        ConfirmDialog(
            icon: "trash",
            tint: DL.live,
            title: "Delete all \(total.formatted()) recordings?",
            message: "Audio and transcripts are removed from this Mac. Statistics are kept. This can't be undone.",
            confirmTitle: "Delete All",
            onCancel: onCancel,
            onConfirm: { onConfirm(starred > 0 && keepStarred) }
        ) {
            if starred > 0 {
                HStack(spacing: 8) {
                    DLCheckbox(isOn: $keepStarred)
                    Text("Keep \(starred) starred recording\(starred == 1 ? "" : "s")")
                        .font(DL.text(12.5, .medium))
                        .foregroundStyle(DL.ink2)
                }
                .onTapGesture { keepStarred.toggle() }
            }
        }
    }
}

// MARK: - Model loading

/// Shown while the speech engine loads (after launch, or after it was released
/// from memory). Names the engine actually being loaded.
struct ModelLoadingOverlay: View {
    @ObservedObject private var settings = SettingsViewModel.shared
    @Environment(\.dlAccent) private var accent

    private var keepInMemoryText: String {
        switch settings.modelIdleUnloadSeconds {
        case 0: return "Release immediately"
        case -1: return "Until quit"
        case 30: return "30 seconds"
        case 60: return "1 minute"
        case 600: return "10 minutes"
        default: return "\(settings.modelIdleUnloadSeconds) s"
        }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            DL.window.opacity(0.35)
            VStack(spacing: 12) {
                ZStack {
                    DLSpinner(size: 58, lineWidth: 4)
                    Image(systemName: "cpu").font(.system(size: 20, weight: .medium)).foregroundStyle(accent.color)
                }
                Text("Loading \(ModelCatalog.activeModelName)…").font(DL.display(18)).foregroundStyle(DL.ink)
                Text(SpeechEngine.current == .parakeet
                     ? "Warming up the Neural Engine. This happens after launch, or when the model was released from memory."
                     : "Loading Whisper onto the GPU. This happens after launch, or when the model was released from memory.")
                    .font(DL.text(12.5))
                    .foregroundStyle(DL.sub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text("Keep in memory: \(keepInMemoryText) ·")
                    Button("Change") { AppRouter.shared.openSettings(.formatting) }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent.color)
                }
                .font(DL.text(11.5, .medium))
                .foregroundStyle(DL.faint)
            }
            .padding(26)
            .frame(width: 380)
            .dlCard(radius: 18)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Drop target

struct DropOverlay: View {
    @Environment(\.dlAccent) private var accent
    @State private var bounce = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            DL.window.opacity(0.55)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.color.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(14)
            VStack(spacing: 14) {
                ZStack {
                    fileCard.rotationEffect(.degrees(-10)).offset(x: -46, y: 8).opacity(0.6)
                    fileCard.rotationEffect(.degrees(9)).offset(x: 46, y: 8).opacity(0.6)
                    fileCard.offset(y: bounce ? -6 : 0)
                }
                .frame(height: 140)
                Text("Drop to transcribe").font(DL.display(24)).foregroundStyle(DL.ink)
                Text("Multiple files are queued in order and transcribed with \(ModelCatalog.activeModelName)")
                    .font(DL.text(13))
                    .foregroundStyle(DL.sub)
                HStack(spacing: 6) {
                    ForEach([".m4a", ".mp3", ".wav", ".aiff", ".flac", ".caf"], id: \.self) { ext in
                        DLTag(text: ext, mono: true)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bounce = true }
        }
    }

    private var fileCard: some View {
        VStack(spacing: 10) {
            IconWell(systemName: "waveform", size: 46)
            Capsule().fill(DL.line).frame(width: 70, height: 6)
        }
        .frame(width: 130, height: 120)
        .dlCard(radius: 16)
    }
}

// MARK: - Permissions

/// Replaces the app until the microphone and accessibility permissions are
/// granted. `PermissionsManager` polls, so this updates on its own.
struct PermissionsGateView: View {
    @ObservedObject var permissionsManager: PermissionsManager
    @Environment(\.dlAccent) private var accent

    private var missingCount: Int {
        (permissionsManager.isMicrophonePermissionGranted ? 0 : 1) + (permissionsManager.isAccessibilityPermissionGranted ? 0 : 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.gradient)
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "checkmark.shield").font(.system(size: 26, weight: .medium)).foregroundStyle(.white))
                    .shadow(color: accent.color.opacity(0.3), radius: 10, y: 4)
                VStack(spacing: 8) {
                    Text(missingCount == 1 ? "One more permission" : "Two permissions needed")
                        .font(DL.display(28))
                        .foregroundStyle(DL.ink)
                    Text("OpenSuperWhisper needs two macOS permissions to work. Audio never leaves your Mac.")
                        .font(DL.text(14))
                        .foregroundStyle(DL.sub)
                        .multilineTextAlignment(.center)
                }
                HStack(alignment: .top, spacing: 14) {
                    PermissionCard(
                        icon: "mic",
                        tint: DL.live,
                        title: "Microphone",
                        detail: "Required to hear you. Only used while the indicator is showing.",
                        granted: permissionsManager.isMicrophonePermissionGranted,
                        buttonTitle: "Grant Access"
                    ) {
                        permissionsManager.requestMicrophonePermissionOrOpenSystemPreferences()
                    }
                    PermissionCard(
                        icon: "keyboard",
                        tint: accent.color,
                        title: "Accessibility",
                        detail: "Lets your shortcut work in every app, and pastes the text where your cursor is.",
                        granted: permissionsManager.isAccessibilityPermissionGranted,
                        buttonTitle: "Open System Settings"
                    ) {
                        permissionsManager.openSystemPreferences(for: .accessibility)
                    }
                }
                .frame(maxWidth: 720)
                if !permissionsManager.isAccessibilityPermissionGranted {
                    HStack(spacing: 12) {
                        (Text("In System Settings").bold() + Text(" › Privacy & Security › Accessibility, switch on OpenSuperWhisper. This window updates on its own."))
                            .font(DL.text(12.5))
                            .foregroundStyle(DL.sub)
                        Spacer()
                        HStack(spacing: 6) {
                            DLSpinner(size: 12)
                            Text("Waiting…").font(DL.text(12)).foregroundStyle(DL.faint)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .dlCard(radius: 14)
                }
            }
            .padding(.vertical, 60)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconWell(systemName: icon, tint: tint, size: 36)
                Text(title).font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                Spacer()
                DLStatusPill(text: granted ? "Granted" : "Needed", kind: granted ? .ok : .warn, icon: granted ? "checkmark" : nil)
            }
            Text(detail).font(DL.text(12.5)).foregroundStyle(DL.sub).fixedSize(horizontal: false, vertical: true)
            if !granted {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "arrow.up.right")
                }
                .buttonStyle(.dlPrimary)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .dlCard(radius: 16, selected: !granted)
    }
}
