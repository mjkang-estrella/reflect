import LocalAuthentication
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingExportDialog = false
    @State private var isExporting = false
    @State private var exportDocument: ExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "VoiceJournal-Export.json"
    @State private var exportError: String?
    @State private var showingPaywall = false
    @State private var entryCount: Int = 0
    @State private var isRestoringPurchases = false
    @State private var restoreAlertTitle: String?
    @State private var restoreAlertMessage: String?
    @State private var showRestoreAlert = false

    private let freeEntryLimit = 30
    private let trialDurationDays = 7
    private let maxAdditionalReminders = 4

    // MARK: - Collapsed Section State
    @State private var isAccountExpanded = true
    @State private var isContentExpanded = true
    @State private var isPrivacyExpanded = false
    @State private var isAboutExpanded = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Account Section (Subscription + Premium Features)
                Section {
                    DisclosureGroup(
                        isExpanded: $isAccountExpanded
                    ) {
                        subscriptionContent
                        if shouldShowPremiumFeaturesList {
                            premiumFeaturesContent
                        }
                    } label: {
                        Label("Account", systemImage: "person.circle.fill")
                            .font(.headline)
                    }
                }

                // MARK: - Content & Recording Section
                Section {
                    DisclosureGroup(
                        isExpanded: $isContentExpanded
                    ) {
                        remindersContent
                        Divider()
                            .padding(.vertical, 4)
                        appearanceContent
                        Divider()
                            .padding(.vertical, 4)
                        audioContent
                        Divider()
                            .padding(.vertical, 4)
                        nudgeContent
                    } label: {
                        Label("Content & Recording", systemImage: "mic.circle.fill")
                            .font(.headline)
                    }
                }

                // MARK: - Privacy & Data Section
                Section {
                    DisclosureGroup(
                        isExpanded: $isPrivacyExpanded
                    ) {
                        syncContent
                        Divider()
                            .padding(.vertical, 4)
                        exportContent
                        Divider()
                            .padding(.vertical, 4)
                        privacyContent
                    } label: {
                        Label("Privacy & Data", systemImage: "lock.shield.fill")
                            .font(.headline)
                    }
                }

                // MARK: - About Section
                Section {
                    DisclosureGroup(
                        isExpanded: $isAboutExpanded
                    ) {
                        aboutContent
                    } label: {
                        Label("About", systemImage: "info.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: "settings")
                    .environmentObject(subscriptionService)
            }
            .onAppear {
                Task {
                    await viewModel.load(using: modelContext)
                    await updateEntryCount()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordingSaved)) { _ in
                Task {
                    await updateEntryCount()
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    exportError = error.localizedDescription
                }
            }
            .confirmationDialog("Export All Data", isPresented: $showingExportDialog) {
                ForEach(SettingsViewModel.ExportFormat.allCases) { format in
                    Button("Export \(format.displayName)") {
                        startExport(format)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a file format to export your journal data.")
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { newValue in
                        if !newValue { exportError = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "Unable to export data.")
            }
            .alert(
                restoreAlertTitle ?? "Restore Purchases",
                isPresented: $showRestoreAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreAlertMessage ?? "Unable to restore purchases.")
            }
        }
    }

    // MARK: - Account Content

    @ViewBuilder
    private var subscriptionContent: some View {
        Group {
            if subscriptionService.isPremium && !subscriptionService.isTrialActive {
                HStack {
                    Text("Current Plan")
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Premium")
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .foregroundColor(.green)
                }

                subscriptionRenewalRow

                Button("Manage Subscription") {
                    openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
                }
            } else if subscriptionService.isTrialActive {
                LabeledContent("Current Plan", value: "Premium Trial")

                if let daysRemaining = subscriptionService.trialDaysRemaining {
                    LabeledContent("Trial ends in", value: "\(daysRemaining) days")
                }

                ProgressView(
                    value: trialProgressValue,
                    total: Double(trialDurationDays)
                )
                .tint(.orange)

                Button("Subscribe now") {
                    showingPaywall = true
                }
            } else {
                LabeledContent("Current Plan", value: "Free")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Entries")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(min(entryCount, freeEntryLimit))/\(freeEntryLimit) used")
                            .foregroundColor(.secondary)
                    }

                    ProgressView(
                        value: min(Double(entryCount), Double(freeEntryLimit)),
                        total: Double(freeEntryLimit)
                    )
                    .tint(.orange)
                }

                if subscriptionService.isTrialEligible {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("Start your 7-day free trial", systemImage: "sparkles")
                    }
                } else {
                    Button("Upgrade to Premium") {
                        showingPaywall = true
                    }
                }
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    Text("Restore Purchases")
                    Spacer()
                    if isRestoringPurchases {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }

            #if DEBUG
                Divider()

                Toggle("Debug: Force Premium", isOn: $subscriptionService.debugForcePremium)
                    .tint(.orange)

                Text("Local testing only. Overrides StoreKit and trial status.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            #endif
        }
    }

    @ViewBuilder
    private var premiumFeaturesContent: some View {
        Group {
            DisclosureGroup("See what's included") {
                ForEach(premiumFeatureRows, id: \.self) { feature in
                    Button {
                        AnalyticsService.track(
                            .premiumFeatureBlocked(feature: "premium_features_list"))
                        showingPaywall = true
                    } label: {
                        HStack {
                            Text(feature)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Content & Recording Content

    @ViewBuilder
    private var remindersContent: some View {
        Text("Reminders")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            Toggle(
                "Daily Reminder",
                isOn: Binding(
                    get: { viewModel.reminderEnabled },
                    set: { enabled in
                        Task {
                            await viewModel.updateReminderEnabled(enabled, using: modelContext)
                        }
                    }
                ))

            DatePicker(
                "Reminder Time",
                selection: Binding(
                    get: { viewModel.reminderTime },
                    set: { time in
                        Task {
                            await viewModel.updateReminderTime(time, using: modelContext)
                        }
                    }
                ),
                displayedComponents: [.hourAndMinute]
            )
            .disabled(!viewModel.reminderEnabled)

            if subscriptionService.hasMultipleReminders {
                ForEach(viewModel.additionalReminderTimes.indices, id: \.self) { index in
                    HStack {
                        DatePicker(
                            "Reminder \(index + 2)",
                            selection: Binding(
                                get: { viewModel.additionalReminderTimes[index] },
                                set: { time in
                                    Task {
                                        await viewModel.updateAdditionalReminder(
                                            time, at: index, using: modelContext
                                        )
                                    }
                                }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )

                        Button {
                            Task {
                                await viewModel.removeAdditionalReminder(
                                    at: index, using: modelContext
                                )
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.additionalReminderTimes.count < maxAdditionalReminders {
                    Button {
                        Task {
                            await viewModel.addAdditionalReminder(using: modelContext)
                        }
                    } label: {
                        Label("Add another reminder", systemImage: "plus")
                    }
                }
            } else {
                Button {
                    AnalyticsService.track(
                        .premiumFeatureBlocked(feature: FeatureType.multipleReminders.rawValue)
                    )
                    showingPaywall = true
                } label: {
                    HStack {
                        Text("Add another reminder")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appearanceContent: some View {
        Text("Appearance")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            Picker(
                "App Appearance",
                selection: Binding(
                    get: { viewModel.themePreference },
                    set: { preference in
                        Task {
                            await viewModel.updateThemePreference(preference, using: modelContext)
                        }
                    }
                )
            ) {
                ForEach(baseThemes, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                Text("Premium Themes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(premiumThemes, id: \.self) { theme in
                        themeCard(for: theme)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioContent: some View {
        Text("Audio Quality")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            Picker(
                "Default Quality",
                selection: Binding(
                    get: { viewModel.audioQuality },
                    set: { quality in
                        Task {
                            await viewModel.updateAudioQuality(quality, using: modelContext)
                        }
                    }
                )
            ) {
                ForEach(AudioQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName)
                        .tag(quality)
                }
            }

            Text(viewModel.audioQuality.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var nudgeContent: some View {
        Text("AI Nudges")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            Toggle(
                "Enable AI Nudges",
                isOn: Binding(
                    get: { viewModel.nudgesEnabled },
                    set: { enabled in
                        Task {
                            await viewModel.updateNudgesEnabled(enabled, using: modelContext)
                        }
                    }
                )
            )
            .disabled(!viewModel.nudgeCapability.isSupported)

            Picker(
                "Frequency",
                selection: Binding(
                    get: { viewModel.nudgeFrequency },
                    set: { frequency in
                        Task {
                            await viewModel.updateNudgeFrequency(frequency, using: modelContext)
                        }
                    }
                )
            ) {
                ForEach(NudgeFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
            .disabled(!viewModel.nudgesEnabled || !viewModel.nudgeCapability.isSupported)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Silence Threshold")
                    Spacer()
                    Text("\(viewModel.nudgeSilenceThreshold, specifier: "%.1fs")")
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { viewModel.nudgeSilenceThreshold },
                        set: { threshold in
                            Task {
                                await viewModel.updateNudgeSilenceThreshold(
                                    threshold, using: modelContext)
                            }
                        }
                    ),
                    in: 3...10,
                    step: 0.5
                )
            }
            .disabled(!viewModel.nudgesEnabled || !viewModel.nudgeCapability.isSupported)

            if subscriptionService.hasCalendarContext {
                Toggle(
                    "Use calendar for smarter prompts",
                    isOn: Binding(
                        get: { viewModel.useCalendarContext },
                        set: { enabled in
                            Task {
                                await viewModel.updateUseCalendarContext(
                                    enabled, using: modelContext
                                )
                            }
                        }
                    )
                )
                .disabled(!viewModel.nudgesEnabled || !viewModel.nudgeCapability.isSupported)
            } else {
                Button {
                    AnalyticsService.track(
                        .premiumFeatureBlocked(feature: FeatureType.calendarContext.rawValue)
                    )
                    showingPaywall = true
                } label: {
                    HStack {
                        Text("Use calendar for smarter prompts")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                        Toggle("", isOn: .constant(viewModel.cloudSyncEnabled))
                            .labelsHidden()
                            .disabled(true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.nudgeCapability.isSupported)
            }

            if let message = viewModel.calendarAuthorizationStatus.message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle(
                "Use mail for smarter prompts",
                isOn: Binding(
                    get: { viewModel.useMailContext },
                    set: { enabled in
                        Task {
                            await viewModel.updateUseMailContext(enabled, using: modelContext)
                        }
                    }
                )
            )
            .disabled(
                !viewModel.nudgesEnabled
                    || !viewModel.nudgeCapability.isSupported
                    || !viewModel.mailCapability.isSupported
            )

            if !viewModel.mailCapability.isSupported {
                Text(viewModel.mailCapability.message ?? "Mail access is unavailable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(
                "Calendar uses event titles and times from today. Mail uses subject lines only. All processing stays on-device and is never stored."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if !viewModel.nudgeCapability.isSupported {
                Text(
                    viewModel.nudgeCapability.message
                        ?? "Apple Intelligence is unavailable on this device."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Privacy & Data Content

    @ViewBuilder
    private var syncContent: some View {
        Text("Sync")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            if subscriptionService.hasCloudSync {
                Toggle(
                    "iCloud Sync",
                    isOn: Binding(
                        get: { viewModel.cloudSyncEnabled },
                        set: { enabled in
                            Task {
                                await viewModel.updateCloudSync(enabled, using: modelContext)
                            }
                        }
                    ))
            } else {
                Button {
                    AnalyticsService.track(
                        .premiumFeatureBlocked(feature: FeatureType.sync.rawValue)
                    )
                    showingPaywall = true
                } label: {
                    HStack {
                        Text("iCloud Sync")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                        Toggle("", isOn: .constant(viewModel.useCalendarContext))
                            .labelsHidden()
                            .disabled(true)
                    }
                }
                .buttonStyle(.plain)
            }

            Text("Sync support is planned for a future update.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var exportContent: some View {
        Text("Export")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            Button("Export All Data") {
                showingExportDialog = true
            }
        }
    }

    @ViewBuilder
    private var privacyContent: some View {
        Text("Privacy")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)

        Group {
            if subscriptionService.isPremium {
                Toggle(
                    "\(biometryName) Lock",
                    isOn: Binding(
                        get: { viewModel.biometricLockEnabled },
                        set: { enabled in
                            Task {
                                await viewModel.updateBiometricLock(enabled, using: modelContext)
                            }
                        }
                    )
                )
                .disabled(!biometryAvailable)
            } else {
                Button {
                    AnalyticsService.track(.premiumFeatureBlocked(feature: "face_id_lock"))
                    showingPaywall = true
                } label: {
                    HStack {
                        Text("\(biometryName) Lock")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                        Toggle("", isOn: .constant(viewModel.biometricLockEnabled))
                            .labelsHidden()
                            .disabled(true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!biometryAvailable)
            }
        }
    }

    // MARK: - About Content

    @ViewBuilder
    private var aboutContent: some View {
        Group {
            LabeledContent("Version", value: appVersion)

            Link("Privacy Policy", destination: privacyURL)
            Link("Terms of Service", destination: termsURL)

            Button("Send Feedback") {
                openURL(feedbackURL)
            }
        }
    }

    private var biometryAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private var biometryName: String {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error)
        if available {
            switch context.biometryType {
            case .faceID:
                return "Face ID"
            case .touchID:
                return "Touch ID"
            default:
                return "Biometric"
            }
        }
        return "Biometric"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--"
        return "\(version) (\(build))"
    }

    private var premiumFeatureRows: [String] {
        [
            "AI nudges while recording",
            "Smart prompts from your calendar",
            "Mood trends and insights",
            "Sync across all devices",
            "Unlimited journal entries",
            "Export to PDF",
            "Custom themes",
            "Multiple reminders",
        ]
    }

    private var shouldShowPremiumFeaturesList: Bool {
        !subscriptionService.isPremium && !subscriptionService.isTrialActive
    }

    private var baseThemes: [ThemePreference] {
        [.system, .light, .dark]
    }

    private var premiumThemes: [ThemePreference] {
        [.sunrise, .ocean, .sage, .midnight]
    }

    private func themeCard(for theme: ThemePreference) -> some View {
        let isSelected = viewModel.themePreference == theme
        let isLocked = theme.isPremium && !subscriptionService.hasCustomThemes

        return Button {
            if isLocked {
                AnalyticsService.track(
                    .premiumFeatureBlocked(feature: FeatureType.customThemes.rawValue)
                )
                showingPaywall = true
                return
            }

            Task {
                await viewModel.updateThemePreference(theme, using: modelContext)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(themeGradient(for: theme))
                    .frame(height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
                    )

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(theme.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.7 : 1)
    }

    private func themeGradient(for theme: ThemePreference) -> LinearGradient {
        switch theme {
        case .system:
            return LinearGradient(
                colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color.white, Color.gray.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color.black.opacity(0.9), Color.black.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunrise:
            return LinearGradient(
                colors: [Color.orange, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ocean:
            return LinearGradient(
                colors: [Color.blue, Color.cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sage:
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.teal.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnight:
            return LinearGradient(
                colors: [Color.indigo, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var trialProgressValue: Double {
        guard let daysRemaining = subscriptionService.trialDaysRemaining else { return 0 }
        let usedDays = max(trialDurationDays - daysRemaining, 0)
        return Double(usedDays)
    }

    private var subscriptionRenewalRow: some View {
        HStack {
            Text(renewalLabel)
            Spacer()
            Text(renewalDateText)
                .foregroundColor(.secondary)

            if isExpiringSoon {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    private var renewalLabel: String {
        if subscriptionService.isAutoRenewEnabled == false {
            return "Expires"
        }
        return "Renews"
    }

    private var renewalDateText: String {
        guard let date = subscriptionService.subscriptionExpirationDate else {
            return "--"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var isExpiringSoon: Bool {
        guard subscriptionService.isAutoRenewEnabled == false,
            let date = subscriptionService.subscriptionExpirationDate
        else {
            return false
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return days >= 0 && days <= 3
    }

    private var privacyURL: URL {
        URL(string: "https://example.com/privacy")!
    }

    private var termsURL: URL {
        URL(string: "https://example.com/terms")!
    }

    private var feedbackURL: URL {
        URL(string: "mailto:feedback@example.com")!
    }

    private func startExport(_ format: SettingsViewModel.ExportFormat) {
        Task {
            do {
                let payload = try await viewModel.exportPayload(format: format, using: modelContext)
                exportContentType = payload.contentType
                exportFilename = payload.filename
                exportDocument = ExportDocument(data: payload.data)
                isExporting = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func updateEntryCount() async {
        let dataService = DataService(modelContext: modelContext)
        entryCount = (try? dataService.entriesCount()) ?? 0
        AnalyticsService.setUserProperty("entryCount", value: entryCount)
    }

    private func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            AnalyticsService.track(.restorePurchasesTapped)
            let wasPremium = subscriptionService.isPremium
            try await subscriptionService.restorePurchases()
            let foundPurchase = subscriptionService.isPremium || wasPremium
            AnalyticsService.track(.restorePurchasesCompleted(foundPurchase: foundPurchase))
            restoreAlertTitle = "Purchases Restored"
            restoreAlertMessage = "Your subscription has been restored."
        } catch {
            AnalyticsService.track(
                .restorePurchasesCompleted(foundPurchase: subscriptionService.isPremium)
            )
            restoreAlertTitle = "Restore Failed"
            restoreAlertMessage = error.localizedDescription
        }
        showRestoreAlert = true
    }
}

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .pdf] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: UserSettings.self, configurations: config)

        return SettingsView()
            .modelContainer(container)
            .environmentObject(SubscriptionService())
    }
#endif
