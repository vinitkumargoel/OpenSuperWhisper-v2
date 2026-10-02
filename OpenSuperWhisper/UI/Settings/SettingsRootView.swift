import SwiftUI

/// The Settings window: a System-Settings-style sidebar of pages on the left,
/// the selected page on the right with back/forward history.
struct SettingsRootView: View {
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var center = ModelDownloadCenter.shared
    @State private var query = ""
    @State private var backStack: [SettingsPage] = []
    @State private var forwardStack: [SettingsPage] = []
    /// Set while back/forward moves the selection, so it isn't pushed again.
    @State private var isTravelling = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
                .background(DL.sidebar)
            Rectangle().fill(DL.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(DL.window)
        }
        .ignoresSafeArea()
        .frame(minWidth: 840, minHeight: 560)
        .onChange(of: router.settingsPage) { oldValue, _ in
            if isTravelling {
                isTravelling = false
            } else {
                backStack.append(oldValue)
                forwardStack.removeAll()
            }
        }
    }

    // MARK: - Sidebar

    private var filteredPages: [SettingsPage] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter { page in
            page.title.lowercased().contains(q) || page.keywords.contains { $0.contains(q) || q.contains($0) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            DLSearchField(placeholder: "Search settings", text: $query)
                .padding(.horizontal, 12)
                .padding(.top, 48)

            brandRow
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Rectangle().fill(DL.line).frame(height: 1).padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filteredPages.isEmpty {
                        Text("No settings match “\(query)”")
                            .font(DL.text(12))
                            .foregroundStyle(DL.faint)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                    }
                    ForEach(filteredPages) { page in
                        if page.startsGroup && query.isEmpty {
                            Spacer().frame(height: 10)
                        }
                        SettingsSidebarRow(
                            title: page.title,
                            icon: page.icon,
                            color: page.color,
                            selected: router.settingsPage == page
                        ) {
                            router.settingsPage = page
                        }
                    }
                    if query.isEmpty || "insights statistics analytics".contains(query.lowercased()) {
                        SettingsSidebarRow(
                            title: "Insights",
                            icon: "chart.bar.fill",
                            color: Color(hex: 0xF59E0B),
                            selected: false,
                            external: true
                        ) {
                            router.show(.insights)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            Link(destination: URL(string: "https://github.com/vinitkumargoel/OpenSuperWhisper-v2")!) {
                HStack(spacing: 6) {
                    Image(systemName: "star")
                    Text("Star on GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
                .font(DL.text(11.5))
                .foregroundStyle(DL.faint)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        }
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("OpenSuperWhisper")
                    .font(DL.text(13, .semibold))
                    .foregroundStyle(DL.ink)
                Text(versionLine)
                    .font(DL.text(11))
                    .foregroundStyle(DL.faint)
                    .lineLimit(1)
            }
        }
    }

    private var versionLine: String {
        _ = center.revision
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "Version \(version) · \(ModelCatalog.activeModelName)"
    }

    // MARK: - Content

    private var header: some View {
        HStack(spacing: 6) {
            Button { goBack() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.dlIcon(size: 26, bordered: false))
                .disabled(backStack.isEmpty)
            Button { goForward() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.dlIcon(size: 26, bordered: false))
                .disabled(forwardStack.isEmpty)
            Text(router.settingsPage.title)
                .font(DL.display(17, .bold))
                .foregroundStyle(DL.ink)
                .padding(.leading, 6)
            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: 52)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var page: some View {
        switch router.settingsPage {
        case .shortcuts: ShortcutsSettingsPage()
        case .audio: AudioSettingsPage()
        case .model: ModelSettingsPage()
        case .transcription: TranscriptionSettingsPage()
        case .formatting: FormattingSettingsPage()
        case .modes: ModesSettingsPage()
        case .appearance: AppearanceSettingsPage()
        case .advanced: AdvancedSettingsPage()
        }
    }

    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(router.settingsPage)
        isTravelling = true
        router.settingsPage = previous
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(router.settingsPage)
        isTravelling = true
        router.settingsPage = next
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let color: Color
    let selected: Bool
    var external = false
    let action: () -> Void
    @Environment(\.dlAccent) private var accent
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconSquare(systemName: icon, color: color, size: 22)
                Text(title)
                    .font(DL.text(13, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.white : DL.ink)
                Spacer(minLength: 4)
                if external {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DL.faint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(accent.color) : AnyShapeStyle(hovering ? DL.well : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
