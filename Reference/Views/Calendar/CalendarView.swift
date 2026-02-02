import SwiftData
import SwiftUI

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CalendarViewModel()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
                    errorState(message: errorMessage)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 20) {
                        calendarHeader

                        weekdayHeader

                        if viewModel.isLoading {
                            loadingCalendarGrid
                        } else {
                            calendarGrid
                        }

                        entriesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Today") {
                        HapticManager.shared.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.goToToday()
                        }
                    }
                    .accessibilityLabel("Jump to today")
                    .accessibilityHint("Moves the calendar to the current date.")
                }
            }
            .refreshable {
                await viewModel.loadEntries(using: modelContext)
            }
            .onAppear {
                Task {
                    await viewModel.loadEntries(using: modelContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordingSaved)) { _ in
                Task {
                    await viewModel.loadEntries(using: modelContext)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
            .animation(.easeInOut(duration: 0.2), value: viewModel.selectedDate)
        }
    }

    private var calendarHeader: some View {
        HStack(spacing: 16) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.moveMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthTitle)
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.moveMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next month")
        }
        .foregroundColor(.primary)
        .padding(.top, 8)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let maxCount = max(viewModel.maxEntryCount(in: viewModel.currentMonth), 1)

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(makeCalendarDays(for: viewModel.currentMonth)) { day in
                CalendarDayCell(
                    day: day,
                    isSelected: calendar.isDate(day.date, inSameDayAs: viewModel.selectedDate),
                    entryCount: viewModel.entryCount(for: day.date),
                    maxEntryCount: maxCount,
                    isStreakDay: viewModel.isStreakDay(day.date)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectDate(day.date)
                    }
                }
                .opacity(day.isInMonth ? 1.0 : 0.35)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -50 {
                        HapticManager.shared.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.moveMonth(by: 1)
                        }
                    } else if value.translation.width > 50 {
                        HapticManager.shared.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.moveMonth(by: -1)
                        }
                    }
                }
        )
    }

    private var loadingCalendarGrid: some View {
        calendarGrid
            .redacted(reason: .placeholder)
            .shimmer()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.selectedDate.dayFormatted)
                    .font(.headline)

                Spacer()

                if !viewModel.selectedEntries.isEmpty {
                    Text("\(viewModel.selectedEntries.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    SkeletonCardView()
                    SkeletonCardView()
                }
                .accessibilityHidden(true)
            } else if viewModel.selectedEntries.isEmpty {
                ContentUnavailableView(
                    "No entries",
                    systemImage: "mic.slash",
                    description: Text("Record a new entry to start a streak.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.selectedEntries, id: \.id) { entry in
                        NavigationLink {
                            JournalEntryDetailView(entry: entry)
                        } label: {
                            HomeEntryCardView(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens entry details.")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 12)
    }

    private var monthTitle: String {
        viewModel.currentMonth.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        let leading = Array(symbols[firstWeekdayIndex...])
        let trailing = Array(symbols[..<firstWeekdayIndex])
        return leading + trailing
    }

    private func makeCalendarDays(for month: Date) -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }

        let monthStart =
            calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let startDate = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: startDate) else {
                return nil
            }
            let isInMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            return CalendarDay(
                date: date,
                isInMonth: isInMonth,
                isToday: calendar.isDateInToday(date)
            )
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            Text(message)
                .font(.headline)

            Text("Please try again in a moment.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Retry") {
                HapticManager.shared.selection()
                Task {
                    await viewModel.loadEntries(using: modelContext)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Reloads your calendar entries.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let isInMonth: Bool
    let isToday: Bool

    var id: Date { date }
}

private struct CalendarDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let entryCount: Int
    let maxEntryCount: Int
    let isStreakDay: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.selection()
            onTap()
        } label: {
            VStack(spacing: 4) {
                Text(dayNumber)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(day.isToday ? .accentColor : .primary)
                    .frame(width: 32, height: 32)
                    .background(dayBackground)
                    .overlay(selectionRing)

                if entryCount > 0 {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }

                if isStreakDay {
                    Capsule()
                        .fill(Color.orange.opacity(0.4))
                        .frame(height: 3)
                        .frame(maxWidth: 26)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(height: 3)
                        .frame(maxWidth: 26)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(entryCount == 0 ? "No entries" : "\(entryCount) entries")
        .accessibilityHint(isStreakDay ? "Part of your streak." : "")
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: day.date))
    }

    private var dayBackground: some View {
        Group {
            if entryCount > 0 {
                Circle()
                    .fill(densityGradient)
            } else {
                Circle()
                    .fill(Color.clear)
            }
        }
    }

    private var selectionRing: some View {
        Group {
            if isSelected {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
            } else if day.isToday {
                Circle()
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            } else {
                Circle()
                    .stroke(Color.clear, lineWidth: 1)
            }
        }
    }

    private var densityGradient: LinearGradient {
        let normalized = min(1, Double(entryCount) / Double(maxEntryCount))
        let startOpacity = 0.12 + (0.2 * normalized)
        let endOpacity = 0.22 + (0.3 * normalized)
        return LinearGradient(
            colors: [
                Color.accentColor.opacity(startOpacity),
                Color.accentColor.opacity(endOpacity),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: day.date)
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: JournalEntry.self, Tag.self, configurations: config)
    let context = container.mainContext

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let sampleDates = [
        today, calendar.date(byAdding: .day, value: -1, to: today),
        calendar.date(byAdding: .day, value: -2, to: today),
        calendar.date(byAdding: .day, value: -5, to: today),
    ]

    for (index, date) in sampleDates.enumerated() {
        if let date {
            let entry = JournalEntry(
                title: "Entry \(index + 1)",
                createdAt: date,
                transcription: "Sample transcription for day \(index + 1).",
                duration: TimeInterval(60 + index * 45),
                tags: ["Sample"]
            )
            context.insert(entry)
        }
    }

    return CalendarView()
        .modelContainer(container)
}
#endif
