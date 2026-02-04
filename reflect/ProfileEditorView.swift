import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingDisplayName") private var displayNameStore = ""
    @AppStorage("onboardingTone") private var toneValueStore = Tone.balanced.rawValue
    @AppStorage("onboardingProactivity") private var proactivityValueStore = Proactivity.medium.rawValue
    @AppStorage("onboardingAvoidTopics") private var avoidTopicsStore = ""

    @State private var profile = ProfileSettings.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var saveSuccess = false

    var body: some View {
        ZStack {
            AppGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView("Loading profile...")
                            .tint(.white)
                            .padding(.top, 24)
                    } else {
                        if let loadError {
                            Text(loadError)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        profileCard

                        if saveSuccess {
                            Text("Saved.")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Edit Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await saveProfile() }
                }
                .disabled(isSaving || isLoading)
            }
        }
        .task {
            await loadProfile()
        }
        .alert(
            "Save Failed",
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

    private var profileCard: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display name")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                TextField("Your name", text: $profile.displayName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tone")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Picker("Tone", selection: $profile.tone) {
                    ForEach(Tone.allCases) { tone in
                        Text(tone.title)
                            .tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Proactivity")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Picker("Proactivity", selection: $profile.proactivity) {
                    ForEach(Proactivity.allCases) { level in
                        Text(level.title)
                            .tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Topics to avoid")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                TextField("Optional — e.g. work, health", text: $profile.avoidTopics, axis: .vertical)
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

    private func loadProfile() async {
        defer { isLoading = false }

        guard let userId = authStore.userId, let userUUID = UUID(uuidString: userId) else {
            loadError = "Sign in to edit your profile."
            profile = profileFromStorage()
            return
        }

        do {
            let repository = try ProfileRepository()
            if let remoteProfile = try await repository.fetchProfile(userId: userUUID) {
                profile = remoteProfile
                syncToStorage(profile)
            } else {
                profile = profileFromStorage()
            }
        } catch {
            loadError = error.localizedDescription
            profile = profileFromStorage()
        }
    }

    private func saveProfile() async {
        guard let userId = authStore.userId, let userUUID = UUID(uuidString: userId) else {
            saveError = "Sign in to save your profile."
            return
        }

        guard !isSaving else { return }
        isSaving = true
        saveSuccess = false
        defer { isSaving = false }

        do {
            let repository = try ProfileRepository()
            try await repository.saveProfile(userId: userUUID, profile: profile)
            syncToStorage(profile)
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func profileFromStorage() -> ProfileSettings {
        ProfileSettings(
            displayName: displayNameStore,
            tone: Tone(rawValue: toneValueStore) ?? .balanced,
            proactivity: Proactivity(rawValue: proactivityValueStore) ?? .medium,
            avoidTopics: avoidTopicsStore
        )
    }

    private func syncToStorage(_ profile: ProfileSettings) {
        displayNameStore = profile.displayName
        toneValueStore = profile.tone.rawValue
        proactivityValueStore = profile.proactivity.rawValue
        avoidTopicsStore = profile.avoidTopics
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        NavigationStack {
            ProfileEditorView()
        }
        .environmentObject(AuthStore())
    }
#endif
