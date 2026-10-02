import SwiftUI

/// Re-runs formatting on a recording's saved raw transcript, optionally with
/// different settings than the live pipeline uses.
struct ReformatPopover: View {
    let recording: Recording

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dlAccent) private var accent
    @State private var options = ReformatOptions.fromCurrentSettings()
    @State private var model: String = AppPreferences.shared.llmModel
    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconWell(systemName: "wand.and.stars", size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reformat").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                    Text("No re-transcription · raw text is kept").font(DL.text(11.5)).foregroundStyle(DL.faint)
                }
            }

            Text("Re-runs formatting on the saved raw transcript. The audio is not re-transcribed, and the raw text is kept so you can compare or reformat again.")
                .font(DL.text(12))
                .foregroundStyle(DL.sub)
                .fixedSize(horizontal: false, vertical: true)

            // Pre-filled from the user's current settings — the point of the
            // button is to reproduce the live pipeline, not to re-specify it.
            DLSegmented(selection: $options.backend, options: FormattingBackend.allCases.map { ($0, $0.title) })

            if options.backend == .s1mini {
                VStack(alignment: .leading, spacing: 9) {
                    axisRow("Styling") {
                        DLSegmented(selection: $options.styling, options: S1Styling.allCases.map { ($0, $0.title) }, size: .small)
                    }
                    axisRow("Structure") {
                        DLSegmented(selection: $options.structure, options: S1Structure.allCases.map { ($0, $0.title) }, size: .small)
                    }
                    axisRow("Context") {
                        DLSegmented(selection: $options.context, options: S1Context.allCases.map { ($0, $0.title) }, size: .small)
                    }
                }
                let installed = S1MiniModelManager.shared.isSelectedInstalled
                HStack(spacing: 6) {
                    Image(systemName: installed ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(installed ? "S1-mini by Superwhisper · installed, runs on this Mac"
                                   : "S1-mini is not downloaded — open Settings › Formatting first.")
                }
                .font(DL.text(11.5, .medium))
                .foregroundStyle(installed ? DL.ok : DL.live)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    DLTextField(placeholder: "Model id", text: $model, mono: true)
                    if !availableModels.isEmpty {
                        DLMenuPicker(selection: $model, items: availableModels.map { ($0, $0) }, width: 130)
                    }
                    Button {
                        fetchModels()
                    } label: {
                        Label(isFetching ? "…" : "Fetch", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.dl(.secondary, size: .small))
                    .disabled(isFetching)
                    .help("List models from the configured endpoint")
                }
                if let fetchError {
                    Text(fetchError).font(DL.text(11.5)).foregroundStyle(DL.live).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Model id, or fetch the list from \(URL(string: AppPreferences.shared.llmBaseURL)?.host ?? "your endpoint")")
                        .font(DL.text(11.5)).foregroundStyle(DL.faint)
                }
            }

            DLDivider()

            HStack {
                Button("Reset to settings") {
                    options = ReformatOptions.fromCurrentSettings()
                    model = AppPreferences.shared.llmModel
                }
                .buttonStyle(.dl(.ghost, size: .small))

                Spacer()

                Button {
                    var chosen = options
                    chosen.model = options.backend == .api ? model : nil
                    run(chosen)
                } label: {
                    Label("Reformat", systemImage: "wand.and.stars")
                }
                .buttonStyle(.dlPrimary)
                .labelStyle(CompactLabelStyle())
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(DL.card)
    }

    private func axisRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink)
            Spacer()
            control()
        }
    }

    private func run(_ chosen: ReformatOptions) {
        Task { @MainActor in
            do {
                dismiss()
                try await TranscriptionQueue.shared.reformatRecording(recording, options: chosen)
            } catch {
                ReformatErrorCenter.shared.report(error)
            }
        }
    }

    private func fetchModels() {
        isFetching = true
        fetchError = nil
        Task { @MainActor in
            defer { isFetching = false }
            do {
                availableModels = try await LLMTextFormatter.fetchAvailableModels(
                    baseURL: AppPreferences.shared.llmBaseURL,
                    apiKey: AppPreferences.shared.llmApiKey
                )
            } catch {
                fetchError = error.localizedDescription
            }
        }
    }
}

/// Reformat errors outlive the popover that started them, so they're surfaced
/// by the Library window rather than the (already dismissed) popover.
@MainActor
final class ReformatErrorCenter: ObservableObject {
    static let shared = ReformatErrorCenter()
    @Published var message: String?

    func report(_ error: Error) {
        message = error.localizedDescription
    }

    /// One-click reformat with the live pipeline's settings.
    func reformatWithCurrentSettings(_ recording: Recording) {
        Task { @MainActor in
            do {
                try await TranscriptionQueue.shared.reformatRecording(recording, options: .fromCurrentSettings())
            } catch {
                report(error)
            }
        }
    }
}
