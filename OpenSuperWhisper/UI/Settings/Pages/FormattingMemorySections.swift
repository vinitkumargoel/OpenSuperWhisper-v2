import SwiftUI

/// Settings › Formatting › Memory: when models load and how long they stay.
struct SettingsMemorySection: View {
    @ObservedObject private var vm = SettingsViewModel.shared

    var body: some View {
        DLSection("Memory") {
            DLToggleRow(
                title: "Load models when recording starts",
                subtitle: "Loading takes a second or two. Doing it while you are still speaking means you never wait for it afterwards.",
                isOn: $vm.prewarmModelsOnRecord
            )
            DLDivider()
            DLRow(
                title: "Keep in memory after use",
                subtitle: vm.modelIdleUnloadSeconds == 0
                    ? "Lowest memory: the transcription model is released before formatting starts, so the two never occupy memory at once."
                    : "Back-to-back dictation reuses the loaded models instead of reloading them."
            ) {
                DLSegmented(
                    selection: $vm.modelIdleUnloadSeconds,
                    options: [
                        (value: 0, label: "Release now"),
                        (value: 30, label: "30 s"),
                        (value: 60, label: "1 min"),
                        (value: 600, label: "10 min"),
                        (value: -1, label: "Until quit"),
                    ],
                    size: .small
                )
            }
            DLDivider()
            HStack(spacing: 10) {
                Image(systemName: "memorychip")
                    .font(.system(size: 12))
                    .foregroundStyle(vm.residencySummary.isEmpty ? DL.faint : DL.ok)
                Text(vm.residencySummary.isEmpty ? "—" : vm.residencySummary)
                    .font(DL.text(11.5, .medium))
                    .foregroundStyle(vm.residencySummary.isEmpty ? DL.faint : DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button {
                    Task { await vm.refreshResidency() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.dl(.ghost, size: .small))
                Button("Unload now") { vm.unloadModelsNow() }
                    .buttonStyle(.dl(.secondary, size: .small))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .task { await vm.refreshResidency() }
    }
}

/// Settings › Formatting › Test formatting: run sample text through the backend.
struct SettingsFormatTestSection: View {
    @ObservedObject private var vm = SettingsViewModel.shared
    @Environment(\.dlAccent) private var accent

    var body: some View {
        DLSection("Test formatting") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Runs the text through the selected backend, exactly as a finished transcript would.")
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
                HStack(alignment: .center, spacing: 12) {
                    DLTextEditor(text: $vm.testInput, mono: true, minHeight: 80)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.color)
                    output
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        vm.runFormatTest()
                    } label: {
                        Label(vm.isTesting ? "Formatting…" : "Format", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.dl(.primary, size: .small))
                    .disabled(vm.isTesting || vm.testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if vm.isTesting { DLSpinner(size: 13) }
                    if !vm.testDuration.isEmpty {
                        Text("\(vm.testDuration) · \(vm.formattingBackend == .s1mini ? "on-device" : "API")")
                            .font(DL.mono(11, .regular))
                            .foregroundStyle(DL.faint)
                    }
                }
            }
            .padding(16)
        }
    }

    private var output: some View {
        ScrollView {
            Group {
                if let error = vm.testError {
                    Text(error).foregroundStyle(DL.live)
                } else if vm.testOutput.isEmpty {
                    Text("The formatted text appears here.").foregroundStyle(DL.faint)
                } else {
                    Text(vm.testOutput).foregroundStyle(DL.ink).textSelection(.enabled)
                }
            }
            .font(DL.text(13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(minHeight: 80, maxHeight: 140)
        .background(RoundedRectangle(cornerRadius: DL.radiusControl, style: .continuous).fill(DL.well.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: DL.radiusControl, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }
}
