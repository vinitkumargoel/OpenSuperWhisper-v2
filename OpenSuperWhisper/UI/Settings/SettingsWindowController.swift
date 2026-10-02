import AppKit
import SwiftUI

/// Settings lives in its own window (like System Settings) rather than a sheet,
/// so it can stay open beside the Library and be reached from the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 840, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsRootView().daylight())
            window.center()
            window.setFrameAutosaveName("OpenSuperWhisperSettings")
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func windowWillClose(_ notification: Notification) {
        // Fall back to a menu-bar-only app when no regular window remains.
        DispatchQueue.main.async {
            let anyVisible = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
