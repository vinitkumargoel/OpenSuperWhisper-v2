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
            RootView()
                .environmentObject(appState)
                .daylight()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Audio Files…") {
                    (NSApp.delegate as? AppDelegate)?.importAudioFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    AppRouter.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(before: .toolbar) {
                Button("Home") { AppRouter.shared.show(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Library") { AppRouter.shared.show(.library) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Insights") { AppRouter.shared.show(.insights) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Search Transcripts") {
                    AppRouter.shared.show(.library)
                    AppRouter.shared.focusSearchRequest += 1
                }
                .keyboardShortcut("k", modifiers: .command)
                Divider()
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
    private var statusPopover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {

        // Before any window is shown, so the title bar doesn't flash the wrong
        // appearance on launch.
        AppearanceManager.shared.start()

        setupStatusBarItem()
        
        if let window = NSApplication.shared.windows.first {
            self.mainWindow = window
            window.delegate = self
            
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 900, height: 600)
            window.maxSize = NSSize(width: 1600, height: 1200)
        }
        
        OpenSuperWhisperApp.startTranscriptionQueue()

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
    
    // MARK: - Menu bar

    /// The status item opens a Daylight panel (record, last transcript, quick
    /// switches, language and microphone pickers) instead of a plain menu.
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

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: StatusPanelView().daylight())
        // Let the popover grow when a picker list in the panel expands.
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        statusPopover = popover
    }

    @objc private func statusBarButtonClicked(_ sender: Any) {
        guard let button = statusItem?.button, let popover = statusPopover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closeStatusPanel() {
        statusPopover?.performClose(nil)
    }

    /// File › Import Audio Files…: queue any audio files the user picks.
    func importAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Import Audio Files"
        panel.prompt = "Transcribe"
        if panel.runModal() == .OK {
            queueAudioURLs(panel.urls)
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
        // Stay a regular app while Settings is still open.
        if !SettingsWindowController.shared.isVisible {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
