import AVFAudio
import AVFoundation
import Speech
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var currentPage = 0
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var isRequestingPermissions = false
    @State private var showTrialConfirmation = false
    @State private var includeTrialPage = false

    private var pages: [OnboardingPage] {
        var items: [OnboardingPage] = [
            OnboardingPage(
                titleKey: "onboarding.title.capture",
                subtitleKey: "onboarding.subtitle.capture",
                systemImage: "mic.fill",
                kind: .standard
            ),
            OnboardingPage(
                titleKey: "onboarding.title.reflect",
                subtitleKey: "onboarding.subtitle.reflect",
                systemImage: "waveform",
                kind: .standard
            ),
            OnboardingPage(
                titleKey: "onboarding.title.permission",
                subtitleKey: "onboarding.subtitle.permission",
                systemImage: "lock.shield.fill",
                kind: .permissions
            ),
        ]

        if includeTrialPage {
            items.append(
                OnboardingPage(
                    titleKey: "onboarding.title.trial",
                    subtitleKey: "onboarding.subtitle.trial",
                    systemImage: "sparkles",
                    kind: .trial
                )
            )
        }

        return items
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 16) {
                header

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(
                            page: page,
                            micGranted: micGranted,
                            speechGranted: speechGranted,
                            isRequesting: isRequestingPermissions,
                            requestPermissions: requestPermissions
                        )
                        .tag(index)
                        .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.25), value: currentPage)

                if isTrialPage {
                    trialFooter
                } else {
                    footer
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            if showTrialConfirmation {
                trialConfirmationToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            refreshPermissionStatus()
            includeTrialPage = subscriptionService.isTrialEligible
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground).opacity(0.95),
                Color.accentColor.opacity(0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("onboarding.skip") {
                HapticManager.shared.selection()
                finishOnboarding()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 24)
            .accessibilityLabel("Skip onboarding")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                guard currentPage > 0 else { return }
                HapticManager.shared.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPage -= 1
                }
            } label: {
                Text("onboarding.back")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == 0)
            .accessibilityLabel("Go back")

            Button {
                HapticManager.shared.impact(.medium)
                if currentPage == pages.count - 1 {
                    finishOnboarding()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPage += 1
                    }
                }
            } label: {
                Text(currentPage == pages.count - 1 ? "onboarding.getStarted" : "onboarding.next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(currentPage == pages.count - 1 ? "Get started" : "Next step")
        }
        .padding(.horizontal, 24)
    }

    private var trialFooter: some View {
        VStack(spacing: 12) {
            Button {
                HapticManager.shared.notification(.success)
                subscriptionService.startTrialIfEligible()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTrialConfirmation = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    finishOnboarding()
                }
            } label: {
                Text("onboarding.trial.start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!subscriptionService.isTrialEligible)
            .accessibilityLabel("Start free trial")

            Button {
                HapticManager.shared.selection()
                finishOnboarding()
            } label: {
                Text("onboarding.trial.later")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Maybe later")
        }
        .padding(.horizontal, 24)
    }

    private var trialConfirmationToast: some View {
        VStack {
            Spacer()
            Text("onboarding.trial.confirmation")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(Color(.secondarySystemBackground))
                )
                .padding(.bottom, 24)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTrialConfirmation = false
                }
            }
        }
    }

    private func finishOnboarding() {
        hasSeenOnboarding = true
    }

    private func refreshPermissionStatus() {
        if #available(iOS 17.0, *) {
            micGranted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        }
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func requestPermissions() {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        HapticManager.shared.impact(.light)

        Task {
            let micService = AudioRecordingService()
            let speechService = SpeechRecognitionService()

            let micResult = await micService.requestPermission()
            let speechResult = await speechService.requestPermission()

            await MainActor.run {
                micGranted = micResult
                speechGranted = speechResult
                isRequestingPermissions = false
                HapticManager.shared.notification(micResult && speechResult ? .success : .warning)
            }
        }
    }

    private var isTrialPage: Bool {
        guard pages.indices.contains(currentPage) else { return false }
        return pages[currentPage].kind == .trial
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let titleKey: String
    let subtitleKey: String
    let systemImage: String
    let kind: OnboardingPageKind
}

private enum OnboardingPageKind {
    case standard
    case permissions
    case trial
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let micGranted: Bool
    let speechGranted: Bool
    let isRequesting: Bool
    let requestPermissions: () -> Void
    @State private var isAnimatingPreview = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: page.systemImage)
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)

            Text(LocalizedStringKey(page.titleKey))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey(page.subtitleKey))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if page.kind == .permissions {
                VStack(spacing: 12) {
                    PermissionRow(
                        titleKey: "onboarding.permission.microphone",
                        isGranted: micGranted
                    )

                    PermissionRow(
                        titleKey: "onboarding.permission.speech",
                        isGranted: speechGranted
                    )

                    Button {
                        requestPermissions()
                    } label: {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(
                                isRequesting
                                    ? "onboarding.permission.requesting"
                                    : "onboarding.permission.allow")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRequesting)
                    .accessibilityLabel("Enable permissions")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            if page.kind == .trial {
                TrialPreviewView(isAnimating: isAnimatingPreview)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            isAnimatingPreview = true
                        }
                    }

                VStack(alignment: .leading, spacing: 10) {
                    TrialFeatureRow(icon: "sparkles", titleKey: "onboarding.trial.feature.nudges")
                    TrialFeatureRow(
                        icon: "wand.and.stars", titleKey: "onboarding.trial.feature.insights")
                    TrialFeatureRow(
                        icon: "infinity", titleKey: "onboarding.trial.feature.unlimited")
                    TrialFeatureRow(icon: "icloud", titleKey: "onboarding.trial.feature.sync")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: micGranted)
        .animation(.easeInOut(duration: 0.25), value: speechGranted)
    }
}

private struct PermissionRow: View {
    let titleKey: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isGranted ? .green : .secondary)

            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)

            Spacer()
        }
        .accessibilityLabel(isGranted ? "\(titleKey) granted" : "\(titleKey) not granted")
    }
}

private struct TrialPreviewView: View {
    let isAnimating: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.2),
                            Color.pink.opacity(0.15),
                            Color(.secondarySystemBackground),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 140)

            VStack(alignment: .leading, spacing: 10) {
                Text("AI Nudge")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Text("\"What felt most meaningful about today?\"")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isAnimating ? 1.2 : 0.8)
                    Text("Listening...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .scaleEffect(isAnimating ? 1.02 : 0.98)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }
}

private struct TrialFeatureRow: View {
    let icon: String
    let titleKey: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 24)

            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        OnboardingView()
            .environmentObject(SubscriptionService())
    }
#endif
