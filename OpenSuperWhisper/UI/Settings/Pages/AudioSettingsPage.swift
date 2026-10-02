import SwiftUI

struct AudioSettingsPage: View {
    @ObservedObject private var vm = SettingsViewModel.shared
    @ObservedObject private var mic = MicrophoneService.shared
    @StateObject private var monitor = MicLevelMonitor()

    private var builtIn: [MicrophoneService.AudioDevice] { mic.availableMicrophones.filter(\.isBuiltIn) }
    private var external: [MicrophoneService.AudioDevice] { mic.availableMicrophones.filter { !$0.isBuiltIn } }

    /// Bluetooth mics switch the headset to call quality when opened, so the
    /// level check waits for a click instead of starting on its own.
    private var currentIsBluetooth: Bool {
        mic.currentMicrophone.map(mic.isBluetoothMicrophone) ?? false
    }

    var body: some View {
        SettingsPageScroll {
            deviceSection
            levelSection
            whileRecordingSection
        }
        .onAppear {
            if !currentIsBluetooth { monitor.start() }
        }
        .onDisappear { monitor.stop() }
        .onChange(of: mic.currentMicrophone) { _, _ in
            if monitor.state == .running { monitor.restart() }
        }
    }

    // MARK: - Devices

    private var deviceSection: some View {
        DLSection("Input device") {
            SettingsDeviceRow(
                title: "Automatic",
                subtitle: "Follows the macOS default — currently \(mic.currentMicrophone?.displayName ?? "none")",
                icon: "sparkles",
                selected: mic.selectedMicrophone == nil,
                active: false
            ) {
                mic.resetToDefault()
            }

            if mic.availableMicrophones.isEmpty {
                DLDivider()
                DLRow(title: "No microphones available", subtitle: "Connect a microphone, then refresh.") { EmptyView() }
            }

            ForEach(builtIn + external) { device in
                DLDivider()
                SettingsDeviceRow(
                    title: device.displayName,
                    subtitle: subtitle(for: device),
                    icon: icon(for: device),
                    selected: mic.selectedMicrophone?.id == device.id,
                    active: mic.currentMicrophone?.id == device.id
                ) {
                    mic.selectMicrophone(device)
                }
            }

            DLDivider()
            HStack {
                Spacer()
                Button {
                    mic.refreshAvailableMicrophones()
                } label: {
                    Label("Refresh devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.dl(.ghost, size: .small))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func subtitle(for device: MicrophoneService.AudioDevice) -> String {
        if device.isBuiltIn { return "Built-in" }
        if mic.isBluetoothMicrophone(device) {
            return "Bluetooth · connects when you start recording, adds about a second"
        }
        if mic.isContinuityMicrophone(device) {
            return "iPhone · connects when you start recording"
        }
        return ["External", device.manufacturer].compactMap { $0 }.joined(separator: " · ")
    }

    private func icon(for device: MicrophoneService.AudioDevice) -> String {
        if device.isBuiltIn { return "laptopcomputer" }
        if mic.isBluetoothMicrophone(device) { return "headphones" }
        if mic.isContinuityMicrophone(device) { return "iphone" }
        return "mic"
    }

    // MARK: - Level

    private var levelSection: some View {
        DLSection("Check your level") {
            HStack(spacing: 14) {
                IconWell(systemName: "mic.fill", tint: DL.live, size: 34)
                VStack(alignment: .leading, spacing: 7) {
                    SettingsLevelMeter(history: monitor.history, live: monitor.state == .running)
                        .frame(height: 22)
                    Text(levelCaption)
                        .font(DL.text(11.5))
                        .foregroundStyle(DL.sub)
                }
                Spacer(minLength: 12)
                levelStatus
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var levelCaption: String {
        switch monitor.state {
        case .noPermission: return "Microphone access is off. Allow it in System Settings › Privacy & Security."
        case .failed(let message): return "Couldn’t open the microphone: \(message)"
        case .idle: return currentIsBluetooth ? "Bluetooth mics switch to call quality while listening, so this starts on request." : "Not listening."
        case .running: return "Speak normally — peaks in the middle of the meter are ideal."
        }
    }

    @ViewBuilder
    private var levelStatus: some View {
        switch monitor.state {
        case .running:
            let peak = monitor.recentPeak
            if peak < 0.25 {
                DLStatusPill(text: "Too quiet", kind: .warn)
            } else if peak > 0.95 {
                DLStatusPill(text: "Too loud", kind: .warn)
            } else {
                DLStatusPill(text: "Good level", kind: .ok)
            }
        case .noPermission:
            DLStatusPill(text: "No access", kind: .live)
        default:
            Button("Test level") { monitor.start() }
                .buttonStyle(.dl(.secondary, size: .small))
        }
    }

    // MARK: - While recording

    private var whileRecordingSection: some View {
        DLSection("While recording") {
            DLToggleRow(
                title: "Mute system sound",
                subtitle: "Also in Shortcuts — music and calls go quiet while you talk",
                isOn: $vm.pauseMediaDuringRecording
            )
            DLDivider()
            DLToggleRow(
                title: "Play start sound",
                subtitle: "A soft click when the mic opens",
                isOn: $vm.playSoundOnRecordStart
            )
        }
    }
}

private struct SettingsDeviceRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    let active: Bool
    let action: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DLRadio(isOn: selected)
                IconWell(systemName: icon, tint: selected ? accent.color : DL.sub, fill: selected ? accent.soft : DL.well, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                    Text(subtitle).font(DL.text(11.5)).foregroundStyle(DL.sub)
                }
                Spacer(minLength: 8)
                if active { DLStatusPill(text: "Active", kind: .ok) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bars from the monitor's history; the newest is on the right.
private struct SettingsLevelMeter: View {
    let history: [Float]
    let live: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            let count = history.count
            let spacing: CGFloat = 3
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(live && value > 0.05 ? accent.color : DL.line)
                        .frame(width: width, height: max(4, CGFloat(value) * geo.size.height))
                }
            }
            .frame(height: geo.size.height)
            .animation(.easeOut(duration: 0.08), value: history)
        }
    }
}
