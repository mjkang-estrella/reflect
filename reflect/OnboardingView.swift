import SwiftUI

struct OnboardingView: View {
    let userId: String
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @AppStorage("onboardingDisplayName") private var displayName = ""
    @AppStorage("onboardingTone") private var toneValue = Tone.balanced.rawValue
    @AppStorage("onboardingProactivity") private var proactivityValue = Proactivity.medium.rawValue
    @AppStorage("onboardingAvoidTopics") private var avoidTopics = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.12, blue: 0.2),
                        Color(red: 0.2, green: 0.22, blue: 0.36),
                        Color(red: 0.88, green: 0.7, blue: 0.6),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(step.title)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .foregroundColor(.white)

                        Text(step.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    switch step {
                    case .welcome:
                        welcomeCard
                    case .tone:
                        toneCard
                    case .preferences:
                        preferencesCard
                    }

                    HStack(spacing: 12) {
                        if step != .welcome {
                            Button("Back") {
                                handleBackAction()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.7))
                        }

                        Button(step.primaryActionTitle) {
                            handlePrimaryAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert(
            "Profile Save Failed",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Unable to save profile.")
        }
    }

    private var welcomeCard: some View {
        VStack(spacing: 16) {
            Text("Let’s personalize your journaling tone and boundaries in three quick steps.")
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Text("You can change these anytime in Profile.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var preferencesCard: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display name")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                TextField("Your name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Proactivity")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Picker("Proactivity", selection: $proactivityValue) {
                    ForEach(Proactivity.allCases) { level in
                        Text(level.title)
                            .tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Topics to avoid")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                TextField("Optional — e.g. work, health", text: $avoidTopics, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(12)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var toneCard: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tone")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Picker("Tone", selection: $toneValue) {
                    ForEach(Tone.allCases) { tone in
                        Text(tone.title)
                            .tag(tone.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func handlePrimaryAction() {
        switch step {
        case .welcome:
            step = .tone
        case .tone:
            step = .preferences
        case .preferences:
            Task {
                await persistProfile()
            }
            onComplete()
        }
    }

    private func handleBackAction() {
        switch step {
        case .welcome:
            return
        case .tone:
            step = .welcome
        case .preferences:
            step = .tone
        }
    }

    private func persistProfile() async {
        guard let userUUID = UUID(uuidString: userId) else { return }

        let profile = ProfileSettings(
            displayName: displayName,
            tone: Tone(rawValue: toneValue) ?? .balanced,
            proactivity: Proactivity(rawValue: proactivityValue) ?? .medium,
            avoidTopics: avoidTopics
        )

        do {
            let repository = try ProfileRepository()
            try await repository.saveProfile(userId: userUUID, profile: profile)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private enum OnboardingStep {
    case welcome
    case tone
    case preferences

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .tone:
            return "Your Tone"
        case .preferences:
            return "Your Boundaries"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "A calmer, clearer journaling experience."
        case .tone:
            return "Choose how your AI nudges should sound."
        case .preferences:
            return "Set your limits for AI nudges."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .welcome:
            return "Get Started"
        case .tone:
            return "Next"
        case .preferences:
            return "Finish"
        }
    }
}

#Preview {
    OnboardingView(userId: "preview") {}
}
