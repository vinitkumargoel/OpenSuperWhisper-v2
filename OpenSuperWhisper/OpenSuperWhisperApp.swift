//
//  OpenSuperWhisperApp.swift
//  OpenSuperWhisper
//
//  Created by user on 05.02.2025.
//

import AVFoundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@main
struct OpenSuperWhisperApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if !appState.hasCompletedOnboarding {
                    OnboardingView()
                        .frame(width: 450)
                } else {
                    ContentView()
                        .frame(minWidth: 860, idealWidth: 980, maxWidth: 1300)
                }
            }
            .frame(minHeight: 480, maxHeight: 1000)
            .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    if let delegate = NSApplication.shared.delegate as? AppDelegate {
                        delegate.showMainWindow()
                    }
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "openMainWindow"))
    }

    init() {
        _ = ShortcutManager.shared
        _ = MicrophoneService.shared
        WhisperModelManager.shared.ensureDefaultModelPresent()
    }
}

extension OpenSuperWhisperApp {
    static func startTranscriptionQueue() {
        Task { @MainActor in
            TranscriptionQueue.shared.startProcessingQueue()
        }
    }
}

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            AppPreferences.shared.hasCompletedOnboarding = hasCompletedOnboarding
        }
    }

    init() {
        var onboarding = AppPreferences.shared.hasCompletedOnboarding
        #if DEBUG
        if let force = DevConfig.shared.forceShowOnboarding {
            onboarding = !force
        }
        #endif
        self.hasCompletedOnboarding = onboarding
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var languageSubmenu: NSMenu?
    private var microphoneService = MicrophoneService.shared
    private var microphoneObserver: AnyCancellable?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        setupStatusBarItem()
        
        if let window = NSApplication.shared.windows.first {
            self.mainWindow = window
            window.delegate = self
            
            window.minSize = NSSize(width: 860, height: 480)
            window.maxSize = NSSize(width: 1300, height: 1100)
        }
        
        OpenSuperWhisperApp.startTranscriptionQueue()
        observeMicrophoneChanges()

        if ProcessInfo.processInfo.environment["OSW_S1_SELFTEST"] != nil {
            runS1SelfTest()
        }
    }

    /// Runs the on-device formatter over the model card's own example and
    /// prints the result, so the whole path can be checked from a terminal
    /// without recording anything. Enabled with OSW_S1_SELFTEST=1.
    private func runS1SelfTest() {
        Task { @MainActor in
            let samples = [
                "so um i need to like send the the report by uh friday no wait make that thursday",
                "i think the answer is forty two no sorry forty three",
                "send it to support at superwhisper dot com",
                "um",
            ]
            print("[S1 self-test] loading...")
            let loadStart = Date()
            do {
                _ = try await S1MiniFormatter.shared.load()
                print(String(format: "[S1 self-test] loaded in %.2fs", Date().timeIntervalSince(loadStart)))
                for sample in samples {
                    let start = Date()
                    let output = try await S1MiniFormatter.shared.format(
                        sample, styling: .semiFormal, structure: .prose, context: .general
                    )
                    print(String(
                        format: "[S1 self-test] %.2fs  in: %@\n[S1 self-test]        out: %@",
                        Date().timeIntervalSince(start), sample, output.isEmpty ? "(empty)" : output
                    ))
                }
                await S1MiniFormatter.shared.unload()

                // Exercise the residency path the real pipeline uses, so
                // "does it actually offload afterwards" is answerable here.
                let idle = AppPreferences.shared.modelIdleUnloadSeconds
                print("[S1 self-test] --- residency check (idle = \(idle)s) ---")
                print("[S1 self-test] formatting enabled: \(AppPreferences.shared.formattingEnabled), backend: \(AppPreferences.shared.formattingBackendValue.rawValue)")

                ModelResidency.shared.recordingDidStart()
                try? await Task.sleep(for: .seconds(2))
                print("[S1 self-test] during recording: \(await ModelResidency.shared.residencySummary())")

                ModelResidency.shared.pipelineDidBegin()
                _ = try? await S1MiniFormatter.shared.format(
                    "so um this is the pipeline test", styling: .semiFormal, structure: .prose, context: .general
                )
                print("[S1 self-test] during pipeline: \(await ModelResidency.shared.residencySummary())")
                ModelResidency.shared.pipelineDidFinish()

                try? await Task.sleep(for: .seconds(max(1, idle) + 3))
                print("[S1 self-test] after idle:      \(await ModelResidency.shared.residencySummary())")
                print("[S1 self-test] done.")
            } catch {
                print("[S1 self-test] FAILED: \(error.localizedDescription)")
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard isAudioFile(url) else {
            return false
        }

        queueAudioURLs([url])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let audioURLs = filenames
            .map { URL(fileURLWithPath: $0) }
            .filter { isAudioFile($0) }

        sender.reply(toOpenOrPrint: audioURLs.isEmpty ? .failure : .success)
        queueAudioURLs(audioURLs)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let audioURLs = urls.filter { isAudioFile($0) }
        queueAudioURLs(audioURLs)
    }

    private func queueAudioURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        Task { @MainActor in
            showMainWindow()

            for url in urls {
                await TranscriptionQueue.shared.addFileToQueue(url: url)
            }
        }
    }

    private func isAudioFile(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .audio)
        }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
    }
    
    private func observeMicrophoneChanges() {
        microphoneObserver = microphoneService.$availableMicrophones
            .sink { [weak self] _ in
                self?.updateStatusBarMenu()
            }
    }
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            if let iconImage = NSImage(named: "tray_icon") {
                iconImage.size = NSSize(width: 48, height: 48)
                iconImage.isTemplate = true
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "OpenSuperWhisper")
            }
            
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }
        
        updateStatusBarMenu()
    }
    
    private func updateStatusBarMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "OpenSuperWhisper", action: #selector(openApp), keyEquivalent: "o"))
        
        let transcriptionLanguageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageSubmenu = NSMenu()
        
        // Add language options
        for languageCode in LanguageUtil.availableLanguages {
            let languageName = LanguageUtil.languageNames[languageCode] ?? languageCode
            let languageItem = NSMenuItem(title: languageName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            languageItem.target = self
            languageItem.representedObject = languageCode
            languageItem.state = (AppPreferences.shared.whisperLanguage == languageCode) ? .on : .off
            languageSubmenu?.addItem(languageItem)
        }
        
        transcriptionLanguageItem.submenu = languageSubmenu
        menu.addItem(transcriptionLanguageItem)
        
        // Listen for language preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languagePreferenceChanged),
            name: .appPreferencesLanguageChanged,
            object: nil
        )
        
        menu.addItem(NSMenuItem.separator())
        
        let microphoneMenu = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let microphones = microphoneService.availableMicrophones
        let currentMic = microphoneService.currentMicrophone
        
        if microphones.isEmpty {
            let noDeviceItem = NSMenuItem(title: "No microphones available", action: nil, keyEquivalent: "")
            noDeviceItem.isEnabled = false
            submenu.addItem(noDeviceItem)
        } else {
            let builtInMicrophones = microphones.filter { $0.isBuiltIn }
            let externalMicrophones = microphones.filter { !$0.isBuiltIn }
            
            for microphone in builtInMicrophones {
                let item = NSMenuItem(
                    title: microphone.displayName,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = microphone
                
                if let current = currentMic, current.id == microphone.id {
                    item.state = .on
                }
                
                submenu.addItem(item)
            }
            
            if !builtInMicrophones.isEmpty && !externalMicrophones.isEmpty {
                submenu.addItem(NSMenuItem.separator())
            }
            
            for microphone in externalMicrophones {
                let item = NSMenuItem(
                    title: microphone.displayName,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = microphone
                
                if let current = currentMic, current.id == microphone.id {
                    item.state = .on
                }
                
                submenu.addItem(item)
            }
        }
        
        microphoneMenu.submenu = submenu
        menu.addItem(microphoneMenu)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? MicrophoneService.AudioDevice else { return }
        microphoneService.selectMicrophone(device)
        updateStatusBarMenu()
    }
    
    @objc private func statusBarButtonClicked(_ sender: Any) {
        statusItem?.button?.performClick(nil)
    }
    
    @objc private func openApp() {
        showMainWindow()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let languageCode = sender.representedObject as? String else { return }
        
        // Update preferences
        AppPreferences.shared.whisperLanguage = languageCode
        
        // Update menu item states
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = .off
            }
            sender.state = .on
        }
    }
    
    @objc private func languagePreferenceChanged() {
        updateLanguageMenuSelection()
    }
    
    private func updateLanguageMenuSelection() {
        guard let languageSubmenu = languageSubmenu else { return }
        
        let currentLanguage = AppPreferences.shared.whisperLanguage
        
        for item in languageSubmenu.items {
            if let languageCode = item.representedObject as? String {
                item.state = (languageCode == currentLanguage) ? .on : .off
            }
        }
    }
    
    func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        
        if let window = mainWindow {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            window.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            let url = URL(string: "openSuperWhisper://openMainWindow")!
            NSWorkspace.shared.open(url)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let width = min(max(frameSize.width, 860), 1300)
        return NSSize(width: width, height: frameSize.height)
    }
}
