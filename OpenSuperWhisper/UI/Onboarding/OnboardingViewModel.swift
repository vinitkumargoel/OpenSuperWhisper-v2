import Foundation
import SwiftUI

enum OnboardingShortcutOption: String, CaseIterable {
    case keyCombination
    case rightOption
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, shortcut, model
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome

    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }

    @Published var useAsianAutocorrect: Bool {
        didSet {
            AppPreferences.shared.useAsianAutocorrect = useAsianAutocorrect
        }
    }

    @Published var selectedShortcut: OnboardingShortcutOption {
        didSet {
            switch selectedShortcut {
            case .keyCombination:
                AppPreferences.shared.modifierOnlyHotkey = ModifierKey.none.rawValue
            case .rightOption:
                AppPreferences.shared.modifierOnlyHotkey = ModifierKey.rightOption.rawValue
            }
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }

    init() {
        let systemLanguage = LanguageUtil.getSystemLanguage()
        AppPreferences.shared.whisperLanguage = systemLanguage
        self.selectedLanguage = systemLanguage
        self.useAsianAutocorrect = AppPreferences.shared.useAsianAutocorrect

        let currentHotkey = ModifierKey(rawValue: AppPreferences.shared.modifierOnlyHotkey) ?? .none
        if currentHotkey == .none && !AppPreferences.shared.hasCompletedOnboarding {
            self.selectedShortcut = .rightOption
            AppPreferences.shared.modifierOnlyHotkey = ModifierKey.rightOption.rawValue
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        } else {
            self.selectedShortcut = currentHotkey == .rightOption ? .rightOption : .keyCombination
        }
    }

    var isAsianLanguage: Bool {
        Settings.asianLanguages.contains(selectedLanguage)
    }

    /// The model step is satisfied once the active model is downloaded and
    /// nothing is still downloading.
    func canFinish(_ center: ModelDownloadCenter) -> Bool {
        guard !center.isDownloading, let active = ModelCatalog.activeModel else { return false }
        return center.isInstalled(active)
    }

    func next() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = next }
        }
    }

    func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = previous }
        }
    }
}
