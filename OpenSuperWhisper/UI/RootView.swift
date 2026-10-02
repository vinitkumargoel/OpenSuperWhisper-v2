import SwiftUI

/// The main window's root: onboarding until it is finished, then the app.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .frame(width: 820, height: 720)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DL.window)
            } else {
                MainView()
                    .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 740)
            }
        }
    }
}
