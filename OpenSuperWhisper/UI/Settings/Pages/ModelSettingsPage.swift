import FluidAudio
import SwiftUI

struct ModelSettingsPage: View {
    @ObservedObject private var center = ModelDownloadCenter.shared

    private var engine: SpeechEngine {
        _ = center.revision
        return SpeechEngine.current
    }

    private var otherEngine: SpeechEngine { engine == .parakeet ? .whisper : .parakeet }

    var body: some View {
        SettingsPageScroll {
            engineSection
            modelSection(for: engine, note: nil)
            modelSection(for: otherEngine, note: "used when the engine is \(otherEngine.title)")
            storageSection
        }
        .onAppear { center.refresh() }
        .alert(item: $center.lastError) { error in
            Alert(
                title: Text("\(error.modelName) didn’t download"),
                message: Text(downloadErrorMessage(error)),
                primaryButton: .default(Text("Try Again")) { center.download(error.model) },
                secondaryButton: .cancel()
            )
        }
    }

    private func downloadErrorMessage(_ error: ModelDownloadCenter.DownloadError) -> String {
        guard error.progressAtFailure > 0 else { return error.message }
        return "Stopped at \(Int(error.progressAtFailure * 100))%. \(error.message)"
    }

    private var engineSection: some View {
        DLSection("Speech recognition engine") {
            HStack(spacing: 12) {
                ForEach(SpeechEngine.allCases) { option in
                    SettingsChoiceCard(
                        title: option.title,
                        subtitle: option.summary,
                        selected: option == engine,
                        action: { center.selectEngine(option) }
                    ) {
                        IconWell(systemName: option.icon, size: 30)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
        }
    }

    private func modelSection(for engine: SpeechEngine, note: String?) -> some View {
        let models = ModelCatalog.models(for: engine)
        let downloadingHere = models.contains { $0.id == center.downloadingID }
        return DLSection("\(engine.title) models", note: note, trailing: {
            if downloadingHere {
                Text("1 downloading").font(DL.text(12)).foregroundStyle(DL.faint)
            }
        }) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                if index > 0 { DLDivider() }
                SettingsModelRow(model: model)
            }
        }
    }

    private var storageSection: some View {
        DLSection("Storage") {
            SettingsFolderRow(
                title: "Whisper models",
                url: WhisperModelManager.shared.modelsDirectory,
                detail: usedText(for: ModelCatalog.whisper)
            )
            DLDivider()
            SettingsFolderRow(
                title: "Parakeet models",
                url: AsrModels.defaultCacheDirectory(for: .v2).deletingLastPathComponent(),
                detail: usedText(for: ModelCatalog.parakeet)
            )
        }
    }

    private func usedText(for models: [SpeechModel]) -> String? {
        let bytes = models.compactMap { center.installedBytes($0) }.reduce(0, +)
        return bytes > 0 ? "\(ModelCatalog.formatBytes(bytes)) used" : nil
    }
}

/// One downloadable model: name and tags, speed/accuracy, and the action that
/// fits its state (Download / progress + Cancel / Use / In use).
struct SettingsModelRow: View {
    let model: SpeechModel
    @ObservedObject private var center = ModelDownloadCenter.shared

    private var isDownloadingThis: Bool { center.downloadingID == model.id }

    var body: some View {
        _ = center.revision
        let installed = center.isInstalled(model)
        let active = center.isActive(model)
        return HStack(spacing: 14) {
            IconWell(systemName: model.engine.icon, tint: active ? nil : DL.sub, fill: active ? nil : DL.well, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name).font(DL.text(13.5, .semibold)).foregroundStyle(DL.ink)
                    if let size = sizeText(installed: installed) { DLTag(text: size, mono: true) }
                    DLTag(text: model.languages)
                    if model.recommended { DLAccentTag(text: "Recommended") }
                }
                Text(isDownloadingThis ? center.progressDetail(for: model) : model.detail)
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
                    .lineLimit(2)
                if isDownloadingThis {
                    DLLinearProgress(progress: center.progress)
                        .frame(maxWidth: 300)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 5) {
                meter("Speed", model.speed)
                meter("Accuracy", model.accuracy)
            }

            action(installed: installed, active: active)
                .frame(minWidth: 130, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isDownloadingThis ? DL.well.opacity(0.35) : .clear)
    }

    private func sizeText(installed: Bool) -> String? {
        if installed, let bytes = center.installedBytes(model) { return ModelCatalog.formatBytes(bytes) }
        return model.sizeText
    }

    private func meter(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).font(DL.text(10.5)).foregroundStyle(DL.faint).frame(width: 48, alignment: .leading)
            DotMeter(value: value)
        }
    }

    @ViewBuilder
    private func action(installed: Bool, active: Bool) -> some View {
        if isDownloadingThis {
            HStack(spacing: 10) {
                DLProgressRing(progress: center.progress, size: 34)
                Button("Cancel") { center.cancel() }
                    .buttonStyle(.dl(.secondary, size: .small))
            }
        } else if active {
            DLStatusPill(text: "In use", kind: .ok, icon: "checkmark.circle")
        } else if installed {
            Button("Use") { center.activate(model) }
                .buttonStyle(.dl(.secondary, size: .small))
        } else {
            Button {
                center.download(model)
            } label: {
                Label(model.sizeText.map { "Download · \($0)" } ?? "Download", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.dl(.secondary, size: .small))
            .disabled(center.isDownloading)
        }
    }
}
