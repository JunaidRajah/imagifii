import SwiftUI

/// Shows the branded startup screen before the queue appears.
struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("imagifiiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .accessibilityLabel(L10n.queueTitle)

                ProgressView()
                    .tint(.accentColor)
            }
        }
    }
}

/// Displays the splash briefly, then presents the main queue.
struct AppRootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ImagifiiView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 1.5)))
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.25)) {
                showSplash = false
            }
        }
    }
}
