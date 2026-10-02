import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsPage: View {
    @ObservedObject private var vm = SettingsViewModel.shared

    private var useModifierKey: Bool { vm.modifierOnlyHotkey != .none }

    /// Same rule as before Daylight: leaving modifier mode clears the key;
    /// entering it picks Left ⌘ when nothing was chosen yet.
    private func setUseModifierKey(_ newValue: Bool) {
        if !newValue {
            vm.modifierOnlyHotkey = .none
        } else if vm.modifierOnlyHotkey == .none {
            vm.modifierOnlyHotkey = .leftCommand
        }
    }

    private var keyCombinationText: String {
        KeyboardShortcuts.getShortcut(for: .toggleRecord)?.description ?? "⌥`"
    }

    var body: some View {
        SettingsPageScroll {
            triggerSection
            behaviourSection
            indicatorSection
        }
    }

    // MARK: - Trigger

    private var triggerSection: some View {
        DLSection("Start recording with") {
            HStack(spacing: 12) {
                SettingsChoiceCard(
                    title: "Key combination",
                    subtitle: "Press two keys together. Works on any keyboard layout.",
                    selected: !useModifierKey,
                    action: { setUseModifierKey(false) }
                ) {
                    Keycap(text: keyCombinationText, minWidth: 30, height: 26)
                }
                SettingsChoiceCard(
                    title: "Single modifier key",
                    subtitle: "One key you rarely press on its own. Fastest to reach mid-sentence.",
                    badge: "Recommended",
                    selected: useModifierKey,
                    action: { setUseModifierKey(true) }
                ) {
                    Keycap(
                        text: useModifierKey ? HotkeyDescription.short(vm.modifierOnlyHotkey) : "Right ⌥",
                        highlighted: useModifierKey,
                        minWidth: 30,
                        height: 26
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)

            DLDivider()

            DLRow(
                title: "Modifier key",
                subtitle: vm.holdToRecord ? "Tap to toggle recording, or hold it to talk" : "One tap toggles recording",
                dimmed: !useModifierKey
            ) {
                DLMenuPicker(
                    selection: Binding(
                        get: { vm.modifierOnlyHotkey == .none ? .leftCommand : vm.modifierOnlyHotkey },
                        set: { vm.modifierOnlyHotkey = $0 }
                    ),
                    items: ModifierKey.allCases.filter { $0 != .none }.map { (value: $0, label: $0.displayName) },
                    width: 190
                )
                .disabled(!useModifierKey)
            }

            DLDivider()

            DLRow(
                title: "Key combination",
                subtitle: useModifierKey ? "Used when Key combination is selected" : "Click to record a new combination",
                dimmed: useModifierKey
            ) {
                KeyboardShortcuts.Recorder("", name: .toggleRecord)
                    .frame(width: 150)
                    .disabled(useModifierKey)
                    .opacity(useModifierKey ? 0.5 : 1)
            }
        }
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        DLSection("Recording behaviour") {
            DLToggleRow(
                title: "Hold to record",
                subtitle: "Hold the shortcut to talk, release to stop. A quick tap toggles instead.",
                isOn: $vm.holdToRecord
            )
            DLDivider()
            DLToggleRow(
                title: "Play sound when recording starts",
                subtitle: "A soft click so you know it’s listening",
                isOn: $vm.playSoundOnRecordStart
            )
            DLDivider()
            DLToggleRow(
                title: "Mute system sound while recording",
                subtitle: "Sets output volume to 0 and restores it when you stop",
                isOn: $vm.pauseMediaDuringRecording
            )
            DLDivider()
            DLToggleRow(
                title: "Launch at login",
                subtitle: "Start OpenSuperWhisper automatically when you log in",
                isOn: $vm.launchAtLogin
            )
            DLDivider()
            DLRow(
                title: "Auto-delete old recordings",
                subtitle: "Removes completed recordings older than this. Starred ones are always kept."
            ) {
                DLMenuPicker(
                    selection: $vm.historyRetentionDays,
                    items: [
                        (value: 0, label: "Never"),
                        (value: 7, label: "7 days"),
                        (value: 30, label: "30 days"),
                        (value: 90, label: "90 days"),
                        (value: 365, label: "1 year"),
                    ],
                    width: 120
                )
            }
        }
    }

    // MARK: - Indicator

    private var indicatorSection: some View {
        DLSection("Floating indicator") {
            HStack(spacing: 8) {
                ForEach(IndicatorPosition.allCases) { position in
                    SettingsPositionTile(position: position, selected: vm.indicatorPosition == position) {
                        vm.indicatorPosition = position
                    }
                }
            }
            .padding(12)

            DLDivider()

            DLRow(title: "Cancel a recording", subtitle: "Discards the audio — nothing is pasted") {
                Keycap(text: "esc", minWidth: 34, height: 24)
            }
        }
    }
}

/// A miniature screen showing where the indicator appears.
private struct SettingsPositionTile: View {
    let position: IndicatorPosition
    let selected: Bool
    let action: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? accent.softer : DL.well.opacity(0.6))
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? accent.color : DL.line, lineWidth: selected ? 2 : 1)
                    miniature.padding(9)
                }
                .frame(height: 58)
                Text(label)
                    .font(DL.text(11, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? accent.color : DL.sub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var label: String {
        switch position {
        case .nearCursor: return "Near text cursor"
        case .topCenter: return "Top center"
        case .bottomCenter: return "Bottom center"
        case .topRight: return "Top right"
        case .bottomRight: return "Bottom right"
        case .hidden: return "Hidden"
        }
    }

    private var pill: some View {
        Capsule()
            .fill(selected ? accent.color : DL.faint.opacity(0.7))
            .frame(width: 26, height: 7)
    }

    @ViewBuilder
    private var miniature: some View {
        switch position {
        case .nearCursor:
            VStack(alignment: .leading, spacing: 4) {
                pill
                HStack(spacing: 1) {
                    Capsule().fill(DL.line).frame(width: 34, height: 4)
                    Rectangle().fill(DL.ink).frame(width: 1.5, height: 10)
                }
            }
        case .topCenter:
            pill.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .bottomCenter:
            pill.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .topRight:
            pill.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        case .bottomRight:
            pill.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        case .hidden:
            Image(systemName: "eye.slash")
                .font(.system(size: 13))
                .foregroundStyle(selected ? accent.color : DL.faint)
        }
    }
}
