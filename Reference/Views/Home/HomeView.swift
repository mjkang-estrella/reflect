import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingCoordinator: RecordingCoordinator
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @StateObject private var viewModel = HomeViewModel()
    @State private var showingLimitSheet = false
    @State private var showingTextEntry = false

    private let freeEntryLimit = 30
    private let recentLimit = 6

    let onSeeAll: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.14, blue: 0.26),
                        Color(red: 0.23, green: 0.23, blue: 0.41),
                        Color(red: 0.91, green: 0.65, blue: 0.62),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

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
            .sheet(isPresented: $showingLimitSheet) {
                LimitReachedSheet(
                    limit: freeEntryLimit,
                    entryCount: viewModel.entryCount,
                    onManageEntries: { onSeeAll() }
                )
                .environmentObject(subscriptionService)
            }
            .sheet(isPresented: $showingTextEntry) {
                TextEntrySheetView {
                    Task {
                        await viewModel.loadEntries(using: modelContext)
                    }
                }
            }
            .refreshable {
                await viewModel.loadEntries(using: modelContext)
            }
            .task {
                await viewModel.loadEntries(using: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordingSaved)) { _ in
                Task {
                    await viewModel.loadEntries(using: modelContext)
                }
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

                Text("Welcome back")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }

    private var weekdayStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { date in
                let isToday = calendar.isDateInToday(date)
                let hasEntry = entryDays.contains(calendar.startOfDay(for: date))

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
            Text("Ready to capture your\nthoughts?")
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
                Text("Last records")
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
                        ForEach(recentEntries, id: \.id) { entry in
                            NavigationLink {
                                JournalEntryDetailView(
                                    entry: entry,
                                    onDelete: {
                                        viewModel.removeEntry(entry)
                                    }
                                )
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

    private func captureButton(title: String, systemImage: String, action: @escaping () -> Void)
        -> some View
    {
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
            showingLimitSheet = true
            return
        }
        recordingCoordinator.startRecording()
    }

    private func handleWriteTap() {
        HapticManager.shared.impact(.medium)
        guard canCreateEntry else {
            showingLimitSheet = true
            return
        }
        showingTextEntry = true
    }

    private var canCreateEntry: Bool {
        subscriptionService.hasUnlimitedEntries || viewModel.entryCount < freeEntryLimit
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

    private var currentStreakCount: Int {
        let days = entryDays
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var currentDay = calendar.startOfDay(for: Date())

        while days.contains(currentDay) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                break
            }
            currentDay = previousDay
        }

        return streak
    }

    private var entryDays: Set<Date> {
        Set(viewModel.entries.map { calendar.startOfDay(for: $0.createdAt) })
    }

    private var weekDates: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }

        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekInterval.start)
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: JournalEntry.self, Tag.self, configurations: config)

    return HomeView(onSeeAll: {})
        .modelContainer(container)
        .environmentObject(RecordingCoordinator())
        .environmentObject(SubscriptionService())
}
#endif
