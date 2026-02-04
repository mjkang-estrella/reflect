import SwiftUI

struct RootView: View {
    @StateObject private var authStore = AuthStore()
    @AppStorage("onboardingUserId") private var onboardingUserId = ""

    var body: some View {
        Group {
            if let configurationError = authStore.configurationError {
                ConfigurationErrorView(message: configurationError)
            } else if !authStore.isReady {
                ProgressView("Loading...")
                    .padding()
            } else if authStore.isAuthenticated, let userId = authStore.userId {
                if onboardingUserId == userId {
                    ContentView()
                } else {
                    OnboardingView(userId: userId) {
                        onboardingUserId = userId
                    }
                }
            } else {
                LoginView()
            }
        }
        .environmentObject(authStore)
        .onOpenURL { url in
            authStore.handleOpenURL(url)
        }
    }
}

private struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.orange)

            Text("Supabase not configured")
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Set SUPABASE_URL and SUPABASE_ANON_KEY in reflect/Info.plist to continue.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#Preview {
    RootView()
}
