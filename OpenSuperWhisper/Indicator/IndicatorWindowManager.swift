import AppKit
import KeyboardShortcuts
import SwiftUI

enum IndicatorPosition: String, CaseIterable, Identifiable {
    case nearCursor
    case topCenter
    case bottomCenter
    case topRight
    case bottomRight
    case hidden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearCursor: return "Near Text Cursor"
        case .topCenter: return "Top Center"
        case .bottomCenter: return "Bottom Center"
        case .topRight: return "Top Right"
        case .bottomRight: return "Bottom Right"
        case .hidden: return "Hidden"
        }
    }

    static var current: IndicatorPosition {
        IndicatorPosition(rawValue: AppPreferences.shared.indicatorPosition) ?? .nearCursor
    }

    /// How the pill anchors inside the (larger, transparent) panel, so it can
    /// grow toward free space when the live transcript expands it.
    var contentAlignment: Alignment {
        switch self {
        case .nearCursor, .bottomCenter: return .bottom
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .bottomRight: return .bottomTrailing
        case .hidden: return .center
        }
    }
}

@MainActor
class IndicatorWindowManager: IndicatorViewDelegate {
    static let shared = IndicatorWindowManager()
    
    var window: NSWindow?
    var viewModel: IndicatorViewModel?
    
    private init() {}
    
    func show(nearPoint point: NSPoint? = nil) -> IndicatorViewModel {

        KeyboardShortcuts.enable(.escape)

        let position = IndicatorPosition.current

        // Create new view model
        let newViewModel = IndicatorViewModel()
        newViewModel.delegate = self
        newViewModel.contentAlignment = position.contentAlignment
        viewModel = newViewModel

        // The recording/transcription state machine lives in the view model, so
        // "hidden" still creates it — we just never put a window on screen.
        if position == .hidden {
            window?.orderOut(nil)
            return newViewModel
        }

        if window == nil {
            // Create window if it doesn't exist - using NSPanel for full-screen compatibility.
            // The panel is deliberately much taller than the pill so the live
            // transcript can grow to its full multi-line height without clipping;
            // the pill anchors to one edge via contentAlignment, so the extra
            // room always extends away from it and nothing shifts on screen.
            // It is transparent and ignores mouse events, so the larger footprint
            // is invisible and non-blocking.
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.isFloatingPanel = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false

            self.window = panel
        }

        // Position window - use the screen containing the point, or main screen as fallback
        let targetScreen = point.flatMap { FocusUtils.screenContaining(point: $0) } ?? NSScreen.main
        if let window = window, let screen = targetScreen {
            let windowFrame = window.frame
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let margin: CGFloat = 24

            var x: CGFloat
            var y: CGFloat

            switch position {
            case .nearCursor:
                if let point = point {
                    // Position near cursor
                    x = point.x - windowFrame.width / 2
                    y = point.y + 20 // 20 points above cursor
                } else {
                    // Default to top center of screen
                    x = screenFrame.midX - windowFrame.width / 2
                    y = screenFrame.maxY - windowFrame.height - 100 // 100 pixels from top
                }
            case .topCenter:
                x = visibleFrame.midX - windowFrame.width / 2
                y = visibleFrame.maxY - windowFrame.height - margin
            case .bottomCenter:
                x = visibleFrame.midX - windowFrame.width / 2
                y = visibleFrame.minY + margin
            case .topRight:
                x = visibleFrame.maxX - windowFrame.width - margin
                y = visibleFrame.maxY - windowFrame.height - margin
            case .bottomRight:
                x = visibleFrame.maxX - windowFrame.width - margin
                y = visibleFrame.minY + margin
            case .hidden:
                x = screenFrame.midX - windowFrame.width / 2
                y = screenFrame.midY
            }

            // Adjust if out of screen bounds
            x = max(screenFrame.minX, min(x, screenFrame.maxX - windowFrame.width))
            y = max(screenFrame.minY, min(y, screenFrame.maxY - windowFrame.height))

            window.setFrameOrigin(NSPoint(x: x, y: y))

            // Set content view
            let hostingView = NSHostingView(rootView: IndicatorWindow(viewModel: newViewModel))
            window.contentView = hostingView
        }

        window?.orderFront(nil)
        return newViewModel
    }
    
    func stopRecording() {
        viewModel?.startDecoding()
    }
    
    func stopForce() {
        viewModel?.cancelRecording()
        viewModel?.cleanup()
        hide()
    }

    func hide() {
        KeyboardShortcuts.disable(.escape)
        
        Task {
            guard let viewModel = self.viewModel else { return }
            
            await viewModel.hideWithAnimation()
            viewModel.cleanup()
            
            self.window?.contentView = nil
            self.window?.orderOut(nil)
            self.viewModel = nil
            
            NotificationCenter.default.post(name: .indicatorWindowDidHide, object: nil)
        }
    }
    
    func didFinishDecoding() {
        hide()
    }
}
