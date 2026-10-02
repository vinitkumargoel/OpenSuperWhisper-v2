import AppKit
import SwiftUI

/// Scrollable body of a settings page: a column of sections with the page's
/// standard margins.
struct SettingsPageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

/// A large selectable card: header art, title (+ optional badge), caption, and
/// a check in the corner. Used for "Start recording with", engines, backends.
struct SettingsChoiceCard<Header: View>: View {
    let title: String
    let subtitle: String
    var badge: String? = nil
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var header: () -> Header
    @Environment(\.dlAccent) private var accent
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    header()
                    Spacer(minLength: 8)
                    SettingsCheckMark(selected: selected)
                }
                .padding(.bottom, 2)
                HStack(spacing: 8) {
                    Text(title)
                        .font(DL.text(13.5, .semibold))
                        .foregroundStyle(DL.ink)
                    if let badge { DLAccentTag(text: badge) }
                }
                Text(subtitle)
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? accent.softer : (hovering ? DL.well.opacity(0.5) : DL.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? accent.color : DL.line, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Filled accent circle with a check, or an empty ring.
struct SettingsCheckMark: View {
    let selected: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(accent.color)
                Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(DL.line, lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// A folder location: title, the path in a mono box, and "Open in Finder".
struct SettingsFolderRow: View {
    let title: String
    let url: URL
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                Text(SettingsPaths.abbreviate(url.path))
                    .font(DL.mono(11, .regular))
                    .foregroundStyle(DL.sub)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(DL.well))
            }
            Spacer(minLength: 12)
            if let detail {
                Text(detail).font(DL.text(12)).foregroundStyle(DL.faint)
            }
            Button {
                SettingsPaths.reveal(url)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
            .buttonStyle(.dl(.secondary, size: .small))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

enum SettingsPaths {
    static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

/// A caption with an info glyph, used under sections.
struct SettingsFootnote: View {
    let text: String
    var icon = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(DL.text(11.5))
        .foregroundStyle(DL.faint)
        .padding(.horizontal, 3)
    }
}

/// Wraps children onto new lines when they run out of width.
struct SettingsFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Label column + content, for editor-style forms (mode editor, S1 style).
struct SettingsFormLine<Content: View>: View {
    let label: String
    var caption: String? = nil
    var labelWidth: CGFloat = 140
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink)
                if let caption {
                    Text(caption).font(DL.text(11)).foregroundStyle(DL.faint)
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
