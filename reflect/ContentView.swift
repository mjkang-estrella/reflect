//
//  ContentView.swift
//  reflect
//
//  Created by MJ Kang on 1/31/26.
//

import Combine
import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var isRecordingPresented = false

    var body: some View {
        Group {
            TabView(selection: $selectedTab) {
                HomeView(
                    onSeeAll: { selectedTab = .history },
                    onRecord: { isRecordingPresented = true }
                )
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(AppTab.history)

                InsightsView()
                    .tabItem {
                        Label("Insights", systemImage: "chart.bar")
                    }
                    .tag(AppTab.insights)

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(AppTab.profile)
            }
        }
        .fullScreenCover(isPresented: $isRecordingPresented) {
            RecordingModeView(isPresented: $isRecordingPresented)
        }
    }
}

enum AppTab: Hashable {
    case home
    case history
    case insights
    case profile
}

struct HomeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel = HomeViewModel()
    @State private var activeSheet: HomeSheet?
    @State private var selectedWeekOffset = 0
    @AppStorage("onboardingDisplayName") private var displayName = ""

    private let freeEntryLimit = 30
    private let recentLimit = 6

    let onSeeAll: () -> Void
    let onRecord: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                ScrollView {
                    VStack(spacing: 32) {
                        headerSection
                        weekdayStrip
                        captureCard
                        lastRecordsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
                case .limit:
                    LimitReachedSheet(limit: freeEntryLimit, entryCount: viewModel.entryCount)
                case .textEntry:
                    TextEntrySheetView()
                }
            }
        .refreshable {
            await viewModel.loadEntries(userId: authStore.userId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalEntriesDidChange)) { _ in
            Task {
                await viewModel.loadEntries(userId: authStore.userId)
            }
        }
        .task {
            await viewModel.loadEntries(userId: authStore.userId)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.entries.count)
    }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(greetingText),")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                Text(welcomeText)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }

    private var weekdayStrip: some View {
        TabView(selection: $selectedWeekOffset) {
            ForEach(weekOffsets, id: \.self) { offset in
                weekRow(for: offset)
                    .tag(offset)
                    .padding(.vertical, 2)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 56)
    }

    private func weekRow(for offset: Int) -> some View {
        let dates = weekDates(for: offset)
        return HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                let isToday = weekCalendar.isDateInToday(date)
                let hasEntry = entryDays.contains(weekCalendar.startOfDay(for: date))

                VStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))

                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isToday ? .white : Color.white.opacity(0.7))

                    Circle()
                        .fill(hasEntry ? Color.white : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var captureCard: some View {
        VStack(spacing: 16) {
            Text("How was your day?")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundColor(Color(red: 0.06, green: 0.08, blue: 0.16))
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                captureButton(
                    title: "Record voice",
                    systemImage: "mic",
                    action: handleRecordTap
                )

                captureButton(
                    title: "Write a text",
                    systemImage: "pencil",
                    action: handleWriteTap
                )
            }

            if currentStreakCount > 0 {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 8, height: 8)

                    Text("You've recorded for \(currentStreakCount) day\(currentStreakCount == 1 ? "" : "s") in a row")
                        .font(.system(size: 12))
                        .foregroundColor(.white)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    Capsule().fill(Color(red: 0.61, green: 0.55, blue: 0.69))
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 16)
        )
    }

    private var lastRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last reflects")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    HapticManager.shared.selection()
                    onSeeAll()
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else if recentEntries.isEmpty {
                Text("No entries yet. Start with a quick note above.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentEntries) { entry in
                            NavigationLink {
                                JournalEntryDetailView(entry: entry)
                            } label: {
                                RecentEntryCardView(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -24)
            }
        }
    }

    private func captureButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.06, green: 0.08, blue: 0.16))

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.06, green: 0.08, blue: 0.16))
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    private func handleRecordTap() {
        HapticManager.shared.impact(.medium)
        guard canCreateEntry else {
            activeSheet = .limit
            return
        }
        onRecord()
    }

    private func handleWriteTap() {
        HapticManager.shared.impact(.medium)
        guard canCreateEntry else {
            activeSheet = .limit
            return
        }
        activeSheet = .textEntry
    }

    private var canCreateEntry: Bool {
        viewModel.entryCount < freeEntryLimit
    }

    private var recentEntries: [JournalEntry] {
        Array(viewModel.entries.prefix(recentLimit))
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var welcomeText: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Welcome back" }
        return "Welcome back, \(trimmed)"
    }

    private var currentStreakCount: Int {
        let days = entryDays
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var currentDay = weekCalendar.startOfDay(for: Date())

        while days.contains(currentDay) {
            streak += 1
            guard let previousDay = weekCalendar.date(byAdding: .day, value: -1, to: currentDay) else {
                break
            }
            currentDay = previousDay
        }

        return streak
    }

    private var entryDays: Set<Date> {
        Set(viewModel.entries.map { weekCalendar.startOfDay(for: $0.createdAt) })
    }

    private var weekOffsets: [Int] {
        Array(-6...6)
    }

    private func weekDates(for offset: Int) -> [Date] {
        let anchorDate = weekCalendar.date(byAdding: .weekOfYear, value: offset, to: Date()) ?? Date()
        let startOfWeek = startOfWeek(for: anchorDate)
        return (0..<7).compactMap { dayOffset in
            weekCalendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        let components = weekCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        var startComponents = DateComponents()
        startComponents.yearForWeekOfYear = components.yearForWeekOfYear
        startComponents.weekOfYear = components.weekOfYear
        startComponents.weekday = 2 // Monday
        let start = weekCalendar.date(from: startComponents) ?? date
        return weekCalendar.startOfDay(for: start)
    }

    private var weekCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }
}

enum HomeSheet: Identifiable {
    case limit
    case textEntry

    var id: Int {
        switch self {
        case .limit:
            return 1
        case .textEntry:
            return 2
        }
    }
}

final class HomeViewModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var entryCount: Int {
        entries.count
    }

    @MainActor
    func loadEntries(userId: String?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard
            let userId,
            let userUUID = UUID(uuidString: userId)
        else {
            errorMessage = "Sign in to see your entries."
            return
        }

        do {
            let repository = try JournalRepository()
            let sessions = try await repository.fetchSessions(userId: userUUID)
            entries = sessions.map { session in
                JournalEntry(
                    id: session.id,
                    createdAt: session.startedAt,
                    title: session.title ?? "",
                    transcription: session.finalText ?? "",
                    duration: TimeInterval(session.durationSeconds ?? 0),
                    tags: session.tags ?? [],
                    mood: Mood(rawValue: session.mood ?? ""),
                    isFavorite: session.isFavorite
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load entries: \(error.localizedDescription)"
        }
    }

    func removeEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
    }
}

struct JournalEntry: Identifiable, Hashable {
    let id: UUID
    var createdAt: Date
    var title: String
    var transcription: String
    var duration: TimeInterval
    var tags: [String]
    var mood: Mood?
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date,
        title: String,
        transcription: String,
        duration: TimeInterval,
        tags: [String],
        mood: Mood? = nil,
        isFavorite: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.transcription = transcription
        self.duration = duration
        self.tags = tags
        self.mood = mood
        self.isFavorite = isFavorite
    }

    static var sampleEntries: [JournalEntry] {
        let now = Date()
        let calendar = Calendar.current
        return [
            JournalEntry(
                createdAt: now,
                title: "On the way home",
                transcription: "I keep thinking about that conversation from today. I don't think I said what I meant.",
                duration: 0,
                tags: ["Thoughts"],
                mood: .reflective,
                isFavorite: false
            ),
            JournalEntry(
                createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                title: "Morning reflection",
                transcription: "The day feels wide open. I want to be intentional about where I put my attention.",
                duration: 112,
                tags: ["Personal", "Mindfulness"],
                mood: .calm,
                isFavorite: true
            ),
            JournalEntry(
                createdAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                title: "Notes from a walk",
                transcription: "Noticed how quiet the street was tonight. The air felt lighter.",
                duration: 0,
                tags: ["Gratitude"],
                mood: .content,
                isFavorite: false
            ),
            JournalEntry(
                createdAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                title: "Work in progress",
                transcription: "I'm still untangling that project. Tomorrow I want to focus on the smallest next step.",
                duration: 64,
                tags: ["Work"],
                mood: .focused,
                isFavorite: false
            ),
            JournalEntry(
                createdAt: calendar.date(byAdding: .day, value: -4, to: now) ?? now,
                title: "Evening recap",
                transcription: "Dinner with friends felt grounding. I should plan more of these.",
                duration: 0,
                tags: ["Friends"],
                mood: .warm,
                isFavorite: false
            ),
            JournalEntry(
                createdAt: calendar.date(byAdding: .day, value: -5, to: now) ?? now,
                title: "Soft reset",
                transcription: "Today was slow. I gave myself permission to rest and let the list wait.",
                duration: 90,
                tags: ["Rest"],
                mood: .relieved,
                isFavorite: false
            ),
        ]
    }
}

enum Mood: String, CaseIterable {
    case calm
    case reflective
    case content
    case focused
    case warm
    case relieved

    var displayName: String {
        rawValue.capitalized
    }
}

struct RecentEntryCardView: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dateText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))

            Text(titleText)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundColor(Color(red: 0.1, green: 0.12, blue: 0.18))
                .lineLimit(2)

            Text(excerptText)
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.35, green: 0.38, blue: 0.45))
                .lineLimit(3)

            Spacer(minLength: 0)

            if let tagText = tagText {
                Text(tagText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.43))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                    )
            }
        }
        .padding(16)
        .frame(width: 180, height: 187, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        Self.dateFormatter.string(from: entry.createdAt)
    }

    private var titleText: String {
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let trimmedTranscription = entry.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = trimmedTranscription.split(whereSeparator: \.isNewline).first {
            return String(firstLine)
        }

        return "Untitled Entry"
    }

    private var excerptText: String {
        let trimmed = entry.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No transcription yet." }

        let lines = trimmed.split(whereSeparator: \.isNewline)
        if lines.count >= 2 {
            return lines.dropFirst().joined(separator: " ")
        }

        return trimmed
    }

    private var tagText: String? {
        if let tag = entry.tags.first {
            return tag
        }
        if let mood = entry.mood {
            return mood.displayName
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM 'at' h:mm a"
        return formatter
    }()
}

struct JournalEntryDetailView: View {
    let entry: JournalEntry

    var body: some View {
        VStack(spacing: 16) {
            Text("Entry Details")
                .font(.title2)
            Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                .font(.headline)
            Text("Placeholder screen")
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TextEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Text Entry")
                    .font(.title2)
                Text("Placeholder screen")
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .navigationTitle("New Text Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LimitReachedSheet: View {
    let limit: Int
    let entryCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("You've reached your free limit")
                .font(.title3.weight(.semibold))

            Text("Free accounts can store up to \(limit) journal entries.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("\(min(entryCount, limit)) of \(limit) entries used")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(24)
    }
}

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                Text("History")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .navigationTitle("History")
        }
    }
}

struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                Text("Insights")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .navigationTitle("Insights")
        }
    }
}

struct ProfileView: View {
    @AppStorage("selectedGradientTheme") private var selectedTheme = AppGradientTheme.dusk.rawValue
    @EnvironmentObject private var authStore: AuthStore
    @State private var showProfileAlert = false
    @State private var signOutError: String?
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Appearance")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Select your gradient mood.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))

                        let columns = [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                        ]

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(AppGradientTheme.allCases) { theme in
                                Button {
                                    selectedTheme = theme.rawValue
                                } label: {
                                    GradientOptionCard(
                                        theme: theme,
                                        isSelected: selectedTheme == theme.rawValue
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Account")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        if let email = authStore.userEmail {
                            Text(email)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        VStack(spacing: 12) {
                            Button {
                                showProfileAlert = true
                            } label: {
                                profileActionRow(
                                    title: "Edit Profile",
                                    systemImage: "person.crop.circle"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                signOut()
                            } label: {
                                profileActionRow(
                                    title: isSigningOut ? "Signing Out..." : "Sign Out",
                                    systemImage: "rectangle.portrait.and.arrow.right",
                                    isDestructive: true
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSigningOut)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Profile")
        }
        .alert("Profile", isPresented: $showProfileAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Profile settings are coming soon.")
        }
        .alert(
            "Sign Out Failed",
            isPresented: Binding(
                get: { signOutError != nil },
                set: { if !$0 { signOutError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                signOutError = nil
            }
        } message: {
            Text(signOutError ?? "Unable to sign out.")
        }
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true

        Task { @MainActor in
            do {
                try await authStore.signOut()
            } catch {
                signOutError = error.localizedDescription
            }
            isSigningOut = false
        }
    }

    private func profileActionRow(
        title: String,
        systemImage: String,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDestructive ? .red.opacity(0.9) : .white)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDestructive ? .red.opacity(0.9) : .white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

enum HapticImpactStyle {
    case medium
}

final class HapticManager {
    static let shared = HapticManager()

    func impact(_ style: HapticImpactStyle) {
        // No-op placeholder for haptics.
    }

    func selection() {
        // No-op placeholder for haptics.
    }
}

#Preview {
    ContentView()
}
