import SwiftUI

struct AdvancedSettingsPage: View {
    @ObservedObject private var vm = SettingsViewModel.shared

    private var isAtDefaults: Bool {
        vm.temperature == 0 && vm.noSpeechThreshold == 0.6 && !vm.useBeamSearch && vm.beamSize == 5
    }

    var body: some View {
        SettingsPageScroll {
            banner

            DLSection("Decoding strategy", badge: "Whisper only") {
                DLToggleRow(
                    title: "Use beam search",
                    subtitle: "Can give better results, but is slower.",
                    isOn: $vm.useBeamSearch
                )
                if vm.useBeamSearch {
                    DLDivider()
                    DLRow(title: "Beam size", subtitle: "Number of candidates explored at each step (1–10)") {
                        DLStepper(value: $vm.beamSize, range: 1...10)
                    }
                }
            }

            DLSection("Model parameters", badge: "Whisper only") {
                DLRow(title: "Temperature", subtitle: "Higher values make the output more random. Keep at 0 for dictation.") {
                    DLSlider(value: $vm.temperature)
                }
                DLDivider()
                DLRow(title: "No-speech threshold", subtitle: "How confident the model must be that a segment is silence before skipping it.") {
                    DLSlider(value: $vm.noSpeechThreshold)
                }
            }

            DLSection("Debug") {
                DLToggleRow(
                    title: "Debug mode",
                    subtitle: "Enable additional logging and debugging information.",
                    isOn: $vm.debugMode
                )
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DL.warn)
            Text("These settings tune the Whisper decoder. Defaults are right for almost everyone.")
                .font(DL.text(12.5))
                .foregroundStyle(DL.ink2)
            Spacer(minLength: 12)
            Button("Restore defaults") {
                vm.temperature = 0
                vm.noSpeechThreshold = 0.6
                vm.useBeamSearch = false
                vm.beamSize = 5
            }
            .buttonStyle(.dl(.secondary, size: .small))
            .disabled(isAtDefaults)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.warnSoft))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DL.warn.opacity(0.25), lineWidth: 1))
    }
}
