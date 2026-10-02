import SwiftUI

struct TranscriptionSettingsPage: View {
    @ObservedObject private var vm = SettingsViewModel.shared

    private var isAsianLanguage: Bool { Settings.asianLanguages.contains(vm.selectedLanguage) }

    private static let punctuationCommands = [
        "new line", "new paragraph", "period", "comma", "question mark",
        "exclamation mark", "colon", "semicolon", "open/close parenthesis",
    ]

    var body: some View {
        SettingsPageScroll {
            languageSection
            outputSection
            promptSection
            DLSection("Storage") {
                SettingsFolderRow(title: "Recordings folder", url: Recording.recordingsDirectory)
            }
        }
    }

    private var languageSection: some View {
        DLSection("Language") {
            DLRow(
                title: "Transcription language",
                subtitle: "Auto-detect is handy for mixed languages but can guess wrong on very short clips."
            ) {
                DLMenuPicker(
                    selection: $vm.selectedLanguage,
                    items: LanguageUtil.availableLanguages.map { code in
                        (value: code, label: LanguageUtil.languageNames[code] ?? code)
                    },
                    width: 160
                )
            }
            DLDivider()
            DLToggleRow(
                title: "Translate to English",
                subtitle: "Whisper only. Speak any language, get English text.",
                isOn: $vm.translateToEnglish
            )
            DLDivider()
            DLRow(
                title: "Use Asian autocorrect",
                subtitle: "Spacing and punctuation fixes for Chinese, Japanese and Korean. Available when one of them is selected.",
                dimmed: !isAsianLanguage
            ) {
                HStack(spacing: 10) {
                    DLTag(text: "zh · ja · ko")
                    DLSwitch(isOn: $vm.useAsianAutocorrect)
                        .disabled(!isAsianLanguage)
                }
            }
        }
    }

    private var outputSection: some View {
        DLSection("Output") {
            DLToggleRow(
                title: "Auto-paste into the focused app",
                subtitle: "When off — or if Accessibility isn’t granted — text is copied to the clipboard instead.",
                isOn: $vm.autoPasteEnabled
            )
            DLDivider()
            DLToggleRow(
                title: "Keep transcript on the clipboard",
                subtitle: "Leave it there after pasting, instead of restoring what was there before.",
                isOn: $vm.keepTranscriptOnClipboard
            )
            DLDivider()
            DLToggleRow(
                title: "Add space after sentence",
                subtitle: "Appends a space when a transcript ends with punctuation, so the next one doesn’t run on.",
                isOn: $vm.addSpaceAfterSentence
            )
            DLDivider()
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spoken punctuation commands")
                        .font(DL.text(13, .semibold))
                        .foregroundStyle(DL.ink)
                    SettingsFlowLayout(spacing: 5, lineSpacing: 5) {
                        Text("Say the words, get the symbols:")
                            .font(DL.text(11.5))
                            .foregroundStyle(DL.sub)
                        ForEach(Self.punctuationCommands, id: \.self) { command in
                            DLTag(text: command)
                        }
                    }
                }
                Spacer(minLength: 12)
                DLSwitch(isOn: $vm.dictationCommandsEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            DLDivider()
            DLToggleRow(
                title: "Suppress blank audio",
                subtitle: "Skip silence instead of transcribing it as “[BLANK_AUDIO]”.",
                isOn: $vm.suppressBlankAudio
            )
            DLDivider()
            DLToggleRow(
                title: "Show timestamps",
                subtitle: "Prefix segments with [00:00:04] markers.",
                isOn: $vm.showTimestamps
            )
        }
    }

    private var promptSection: some View {
        DLSection("Initial prompt") {
            VStack(alignment: .leading, spacing: 10) {
                DLTextEditor(text: $vm.initialPrompt, minHeight: 84)
                HStack {
                    Text("Optional text that nudges the model’s spelling and style. Product names you say often belong here.")
                        .font(DL.text(11.5))
                        .foregroundStyle(DL.faint)
                    Spacer(minLength: 12)
                    Button {
                        vm.initialPrompt = AppPreferences.defaultInitialPrompt
                    } label: {
                        Label("Restore default", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.dl(.ghost, size: .small))
                    .disabled(vm.initialPrompt == AppPreferences.defaultInitialPrompt)
                }
            }
            .padding(16)
        }
    }
}
