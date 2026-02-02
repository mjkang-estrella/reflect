import SwiftData
import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionService: SubscriptionService

    @StateObject private var viewModel: RecordingViewModel
    @StateObject private var nudgeService = NudgeService()
    @Query private var userSettings: [UserSettings]
    @State private var showCancelConfirmation = false
    @State private var lastRecordingState: RecordingState = .idle
    @State private var showingPaywall = false
    @State private var paywallSource = "recording"
    @State private var showPremiumHint = false
    @State private var showNudgeUpsellCard = false
    @AppStorage("nudgesUpsellShownCount") private var nudgesUpsellShownCount: Int = 0
    @AppStorage("nudgesUpsellLastShown") private var nudgesUpsellLastShown: Double = 0
    @State private var showFullTranscription = false

    var onSave: ((JournalEntry) -> Void)?

    init(dataService: DataService, onSave: ((JournalEntry) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: RecordingViewModel(dataService: dataService))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient

                VStack(spacing: 0) {
                    // Timer display
                    timerDisplay
                        .padding(.top, 40)

                    // Waveform visualization
                    waveformSection
                        .padding(.vertical, 30)

                    // Transcription preview
                    transcriptionPreview
                        .padding(.horizontal)

                    Spacer()

                    // Recording controls
                    controlsSection
                        .padding(.bottom, 50)
                }

                nudgeOverlay

                if showNudgeUpsellCard {
                    VStack {
                        Spacer()
                        nudgeUpsellCard
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.recordingState.isActive {
                        Button("Cancel") {
                            showCancelConfirmation = true
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    recordingStatusIndicator
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.recordingState.isActive {
                        DoneRecordingButton(isEnabled: viewModel.canSave) {
                            Task {
                                await saveRecording()
                            }
                        }
                    }
                }
            }
            .alert("Cancel Recording?", isPresented: $showCancelConfirmation) {
                Button("Continue Recording", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    viewModel.cancelRecording()
                }
            } message: {
                Text("Your recording will be discarded and cannot be recovered.")
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: paywallSource)
                    .environmentObject(subscriptionService)
            }
            .sheet(isPresented: $showFullTranscription) {
                FullTranscriptionView(
                    transcription: viewModel.transcriptionText,
                    isRecording: viewModel.isRecording
                )
            }
            .alert("Recording Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
            }
            .onAppear {
                Task { await ensureUserSettings() }
                nudgeService.updatePreferences(nudgePreferences)
            }
            .onChange(of: nudgePreferences) { newValue in
                nudgeService.updatePreferences(newValue)
            }
            .onChange(of: subscriptionService.hasAINudges) { hasEntitlement in
                if !hasEntitlement {
                    nudgeService.endSession()
                    nudgeService.dismissCurrentNudge()
                } else if viewModel.isRecording, nudgePreferences.isEnabled {
                    nudgeService.beginSession()
                }
            }
            .onChange(of: subscriptionService.isPremium) { isPremium in
                if isPremium && showNudgeUpsellCard {
                    showNudgeUpsellCard = false
                    dismiss()
                }
            }
            .onChange(of: viewModel.recordingState) { newValue in
                handleRecordingStateChange(newValue)
            }
            .onChange(of: viewModel.transcriptionResult) { result in
                guard subscriptionService.hasAINudges else { return }
                nudgeService.handleTranscriptionUpdate(
                    text: result.text,
                    segments: result.segments,
                    currentTime: viewModel.currentTime,
                    isRecording: viewModel.isRecording
                )
            }
            .onChange(of: viewModel.audioLevels) { levels in
                guard subscriptionService.hasAINudges else { return }
                nudgeService.handleAudioLevel(
                    levels.last ?? 0,
                    currentTime: viewModel.currentTime,
                    isRecording: viewModel.isRecording
                )
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground).opacity(0.95),
                viewModel.isRecording ? Color.red.opacity(0.05) : Color(.systemBackground),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: viewModel.isRecording)
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(viewModel.formattedTimeWithMilliseconds)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.1), value: viewModel.currentTime)

            if viewModel.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .transition(.opacity.combined(with: .scale))
            } else if viewModel.isRecording {
                Label("Recording", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .symbolEffect(
                        .variableColor.iterative.reversing, isActive: viewModel.isRecording)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.recordingState)
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        LiveWaveformView(
            audioLevels: viewModel.audioLevels,
            isRecording: viewModel.isRecording,
            isPaused: viewModel.isPaused
        )
        .frame(height: 120)
        .padding(.horizontal, 20)
    }

    // MARK: - Transcription Preview

    private var transcriptionPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundColor(.secondary)
                Text("Live Transcription")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                if nudgeService.isAvailable {
                    nudgeToggleButton
                }

                #if DEBUG
                    if nudgeService.isAvailable {
                        Button {
                            nudgeService.debugShowTestNudge()
                        } label: {
                            Text("Test")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                #endif

                if viewModel.isRecording && !viewModel.transcriptionText.isEmpty {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            ScrollView {
                Text(
                    viewModel.transcriptionText.isEmpty
                        ? "Start speaking to see transcription..." : viewModel.transcriptionText
                )
                .font(.body)
                .foregroundColor(viewModel.transcriptionText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: viewModel.transcriptionText)
            }
            .frame(height: 120)

            // Expand button when there's content
            if !viewModel.transcriptionText.isEmpty {
                Button {
                    HapticManager.shared.selection()
                    showFullTranscription = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                        Text("View full transcription")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.transcriptionText.isEmpty)
    }

    // MARK: - Nudges

    private var nudgePreferences: NudgeService.Preferences {
        guard let settings = userSettings.first else {
            return .default
        }

        return NudgeService.Preferences(
            isEnabled: settings.nudgesEnabled && subscriptionService.hasAINudges,
            frequency: settings.nudgeFrequency,
            silenceThreshold: settings.nudgeSilenceThreshold,
            useCalendarContext: settings.useCalendarContext,
            useMailContext: settings.useMailContext
        )
    }

    private var nudgeToggleButton: some View {
        Button {
            guard subscriptionService.hasAINudges else {
                AnalyticsService.track(.premiumFeatureBlocked(feature: FeatureType.nudges.rawValue))
                showPremiumHint = true
                paywallSource = "recording_nudge_toggle"
                showingPaywall = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showPremiumHint = false
                }
                return
            }

            let nextValue = !(userSettings.first?.nudgesEnabled ?? true)
            Task { await updateNudgesEnabled(nextValue) }
        } label: {
            ZStack {
                Image(systemName: nudgeToggleSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(subscriptionService.hasAINudges ? .orange : .secondary)

                if !subscriptionService.hasAINudges {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .offset(x: 10, y: 10)
                }
            }
            .padding(6)
            .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .opacity(subscriptionService.hasAINudges ? 1 : 0.6)
        .accessibilityLabel(
            subscriptionService.hasAINudges
                ? ((userSettings.first?.nudgesEnabled ?? true)
                    ? "Disable AI nudges" : "Enable AI nudges")
                : "Premium feature"
        )
        .overlay(alignment: .bottomTrailing) {
            if showPremiumHint && !subscriptionService.hasAINudges {
                Text("Premium feature")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .offset(x: 0, y: 18)
                    .transition(.opacity)
            }
        }
    }

    private var nudgeToggleSymbolName: String {
        let enabled = userSettings.first?.nudgesEnabled ?? true
        if subscriptionService.hasAINudges, enabled {
            return "sparkles"
        }

        if #available(iOS 17.0, *) {
            return "sparkles.slash"
        }

        return "sparkles"
    }

    private var nudgeOverlay: some View {
        Group {
            if subscriptionService.hasAINudges && nudgeService.isAvailable {
                GeometryReader { proxy in
                    if nudgeService.isThinking || nudgeService.currentNudge != nil {
                        VStack {
                            Spacer()
                            nudgeCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, overlayBottomPadding(using: proxy))
                                .transition(.opacity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.25), value: nudgeService.currentNudge?.id)
                        .animation(.easeInOut(duration: 0.25), value: nudgeService.isThinking)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nudgeCard: some View {
        if let nudge = nudgeService.currentNudge {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)

                    if nudge.contextSources.contains(.calendar) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if nudge.contextSources.contains(.mail) {
                        Image(systemName: "envelope")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(nudge.text)
                        .font(.callout)
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 12)

                Button {
                    nudgeService.dismissCurrentNudge()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .onTapGesture {
                nudgeService.dismissCurrentNudge()
            }
        } else if nudgeService.isThinking {
            HStack(spacing: 12) {
                ProgressView()
                Text("Thinking...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func overlayBottomPadding(using proxy: GeometryProxy) -> CGFloat {
        let basePadding: CGFloat = viewModel.recordingState.isActive ? 170 : 120
        return max(basePadding, proxy.safeAreaInsets.bottom + 140)
    }

    // MARK: - Recording Status Indicator

    private var recordingStatusIndicator: some View {
        HStack(spacing: 6) {
            if viewModel.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
            }

            Text(statusText)
                .font(.headline)
        }
    }

    private var statusText: String {
        switch viewModel.recordingState {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .processing:
            return "Processing..."
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 30) {
            if viewModel.recordingState.isActive {
                // Active recording controls
                HStack(spacing: 60) {
                    CancelRecordingButton {
                        showCancelConfirmation = true
                    }

                    ZStack(alignment: .topTrailing) {
                        RecordButton(
                            isRecording: viewModel.isRecording,
                            isPaused: viewModel.isPaused,
                            isProcessing: viewModel.isProcessing,
                            audioLevel: viewModel.audioLevels.last ?? 0
                        ) {
                            if viewModel.isPaused {
                                viewModel.resumeRecording()
                            } else {
                                viewModel.pauseRecording()
                            }
                        }

                        if subscriptionService.hasAINudges
                            && nudgeService.isAvailable
                            && (userSettings.first?.nudgesEnabled ?? false)
                        {
                            aiBadge
                        }
                    }

                    PauseResumeButton(isPaused: viewModel.isPaused) {
                        if viewModel.isPaused {
                            viewModel.resumeRecording()
                        } else {
                            viewModel.pauseRecording()
                        }
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                // Idle state - show record button
                VStack(spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        RecordButton(
                            isRecording: false,
                            isPaused: false,
                            isProcessing: viewModel.isProcessing,
                            audioLevel: 0
                        ) {
                            Task {
                                await viewModel.startRecording()
                            }
                        }

                        if subscriptionService.hasAINudges
                            && nudgeService.isAvailable
                            && (userSettings.first?.nudgesEnabled ?? false)
                        {
                            aiBadge
                        }
                    }

                    Text("Tap to start recording")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .transition(
                    .asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.recordingState)
    }

    // MARK: - Actions

    private func saveRecording() async {
        if let entry = await viewModel.stopAndSave() {
            onSave?(entry)

            if shouldShowNudgeUpsell() {
                recordNudgeUpsellShown()
                showNudgeUpsellCard = true
            } else {
                dismiss()
            }
        }
    }

    @MainActor
    private func ensureUserSettings() async {
        do {
            let dataService = DataService(modelContext: modelContext)
            _ = try dataService.fetchUserSettings()
            try dataService.save()
        } catch {
            // Best effort; settings can be recreated later if needed.
        }
    }

    @MainActor
    private func updateNudgesEnabled(_ enabled: Bool) async {
        do {
            let dataService = DataService(modelContext: modelContext)
            try dataService.updateUserSettings(nudgesEnabled: enabled)
            try dataService.save()
        } catch {
            // Ignore persistence failures to keep UI responsive.
        }
    }

    private func handleRecordingStateChange(_ newState: RecordingState) {
        if lastRecordingState == .idle && newState == .recording {
            showNudgeUpsellCard = false
            if subscriptionService.hasAINudges && nudgePreferences.isEnabled {
                nudgeService.beginSession()
            }
        } else if lastRecordingState == .recording && newState == .paused {
            nudgeService.pauseSession()
        } else if lastRecordingState.isActive && !newState.isActive {
            nudgeService.endSession()
        }

        lastRecordingState = newState
    }

    // MARK: - AI Badge

    private var aiBadge: some View {
        Text("AI")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange))
            .foregroundColor(.white)
            .offset(x: 14, y: -14)
            .transition(.opacity)
    }

    // MARK: - Upsell Card

    private var nudgeUpsellCard: some View {
        VStack(spacing: 12) {
            Text("Premium users get AI follow-up questions while recording.")
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Not now") {
                    showNudgeUpsellCard = false
                    dismiss()
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)

                Button("Try it free") {
                    AnalyticsService.track(.premiumFeatureBlocked(feature: "nudges_upsell"))
                    paywallSource = "recording_nudge_upsell"
                    showingPaywall = true
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.orange))
                .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func shouldShowNudgeUpsell() -> Bool {
        guard !subscriptionService.hasAINudges else { return false }
        let now = Date()
        let lastShown = Date(timeIntervalSince1970: nudgesUpsellLastShown)
        let daysSinceLast =
            Calendar.current.dateComponents([.day], from: lastShown, to: now).day ?? 0
        return nudgesUpsellShownCount < 3 || daysSinceLast >= 7
    }

    private func recordNudgeUpsellShown() {
        nudgesUpsellShownCount += 1
        nudgesUpsellLastShown = Date().timeIntervalSince1970
    }
}

// MARK: - Full Transcription View

struct FullTranscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    let transcription: String
    let isRecording: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if transcription.isEmpty {
                        Text("No transcription yet. Start speaking to see text appear here.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        Text(transcription)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Full Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Recording")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !transcription.isEmpty {
                    VStack(spacing: 8) {
                        Text("\(transcription.split(separator: " ").count) words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }
}

// MARK: - Pulsing Modifier

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Preview

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        // Create a mock DataService for preview
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: JournalEntry.self, UserSettings.self, configurations: config)
        let dataService = DataService(modelContext: container.mainContext)

        return RecordingView(dataService: dataService)
            .environmentObject(SubscriptionService())
    }
#endif
