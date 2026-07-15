import Foundation
import AppKit

/// A named LLM-formatting preset. Each mode carries its own system prompt and,
/// optionally, a set of app bundle identifiers that auto-activate it when one
/// of those apps was frontmost at the moment recording started.
struct FormattingMode: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    /// App bundle IDs that auto-select this mode (e.g. "com.apple.mail").
    var appBundleIDs: [String]

    init(id: UUID = UUID(), name: String, prompt: String, appBundleIDs: [String] = []) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.appBundleIDs = appBundleIDs
    }
}

extension AppPreferences {
    /// Resolves the system prompt to use for the current formatting request.
    ///
    /// Priority: an app-matched mode (when auto-switch is on and the captured
    /// frontmost app matches) → the manually-selected active mode → the first
    /// mode → the legacy single prompt.
    func resolveFormattingPrompt() -> String {
        let modes = formattingModes
        guard !modes.isEmpty else {
            let legacy = formattingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return legacy.isEmpty ? AppPreferences.defaultFormattingPrompt : legacy
        }

        if autoSwitchFormattingMode,
           let bundleID = FocusUtils.lastFrontmostBundleID,
           let matched = modes.first(where: { $0.appBundleIDs.contains(bundleID) }) {
            return resolvedPrompt(for: matched)
        }

        if let active = modes.first(where: { $0.id.uuidString == activeFormattingModeID }) {
            return resolvedPrompt(for: active)
        }

        return resolvedPrompt(for: modes[0])
    }

    private func resolvedPrompt(for mode: FormattingMode) -> String {
        let trimmed = mode.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppPreferences.defaultFormattingPrompt : trimmed
    }
}
