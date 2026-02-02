import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @StateObject private var viewModel = InsightsViewModel()

    private let moodOrder: [Mood] = Mood.allCases
    private let statsColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]
    private let statsColumnsCompact = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading {
                    InsightsSkeletonView()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                        .accessibilityHidden(true)
                } else if let errorMessage = viewModel.errorMessage {
                    errorState(message: errorMessage)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 24) {
                        if subscriptionService.hasInsights {
                            statsSection
                            moodTrendSection
                            tagsSection
                            streakSection
                            onThisDaySection
                            weeklySummarySection
                            monthlyTrendsSection
                        } else {
                            statsSectionFree
                            upgradePromptSection
                            onThisDaySection
                            lockedMoodTrendSection
                            lockedTagsSection
                            lockedWeeklySummarySection
                            lockedMonthlyTrendsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Insights")
            .refreshable {
                await viewModel.load(
                    using: modelContext, includeSummary: subscriptionService.hasInsights)
            }
            .onAppear {
                Task {
                    await viewModel.load(
                        using: modelContext, includeSummary: subscriptionService.hasInsights)
                }
            }
            .onChange(of: subscriptionService.hasInsights) { _ in
                Task {
                    await viewModel.load(
                        using: modelContext, includeSummary: subscriptionService.hasInsights)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordingSaved)) { _ in
                Task {
                    await viewModel.load(
                        using: modelContext, includeSummary: subscriptionService.hasInsights)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
        }
    }

    private var statsSection: some View {
        LazyVGrid(columns: statsColumns, spacing: 12) {
            StatCardView(
                title: "Total Entries",
                value: "\(viewModel.totalEntries)",
                icon: "waveform"
            )
            StatCardView(
                title: "Recording Time",
                value: formattedDuration(viewModel.totalDuration),
                icon: "timer"
            )
            StatCardView(
                title: "Current Streak",
                value: "\(viewModel.currentStreakCount) days",
                icon: "flame.fill"
            )
            StatCardView(
                title: "Top Tags",
                value: "\(viewModel.tagCounts.prefix(3).map(\.name).joined(separator: ", "))",
                icon: "tag.fill"
            )
        }
    }

    private var statsSectionFree: some View {
        LazyVGrid(columns: statsColumnsCompact, spacing: 12) {
            StatCardView(
                title: "Current Streak",
                value: "\(viewModel.currentStreakCount) days",
                icon: "flame.fill"
            )
            StatCardView(
                title: "Total Entries",
                value: "\(viewModel.totalEntries)",
                icon: "waveform"
            )
            StatCardView(
                title: "Recording Time",
                value: formattedDuration(viewModel.totalDuration),
                icon: "timer"
            )
        }
    }

    private var upgradePromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UpgradePromptCard(
                icon: "sparkles",
                message: "Unlock your insights",
                analyticsFeature: "insights_upgrade",
                paywallSource: "insights_upgrade"
            )

            HStack(spacing: 8) {
                PreviewChip(text: "Mood trends")
                PreviewChip(text: "Tag analytics")
                PreviewChip(text: "Weekly AI summary")
                PreviewChip(text: "Monthly trends")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var moodTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood Trends")
                .font(.headline)

            if viewModel.moodTrend.isEmpty {
                ContentUnavailableView(
                    "No mood data yet",
                    systemImage: "face.smiling",
                    description: Text("Add moods to entries to see trends.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                Chart(viewModel.moodTrend) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Mood", point.mood.displayName)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Mood", point.mood.displayName)
                    )
                    .symbolSize(30)
                }
                .chartYScale(domain: moodOrder.map(\.displayName))
                .chartYAxis {
                    AxisMarks(values: moodOrder.map(\.displayName)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityLabel("Mood trends chart")
            }
        }
    }

    private var lockedMoodTrendSection: some View {
        lockedSection(title: "Mood Trends") {
            LockedChartPlaceholder(height: 220)
        }
        .lockedFeatureOverlay(isLocked: true, feature: "insights_mood_trends")
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Used Tags")
                .font(.headline)

            if viewModel.tagCounts.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Tag your entries to surface topics.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                Chart(viewModel.tagCounts.prefix(8)) { item in
                    BarMark(
                        x: .value("Tag", item.name),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(6)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityLabel("Most used tags chart")
            }
        }
    }

    private var lockedTagsSection: some View {
        lockedSection(title: "Most Used Tags") {
            LockedChartPlaceholder(height: 200)
        }
        .lockedFeatureOverlay(isLocked: true, feature: "insights_tags")
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Streaks & Activity")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.currentStreakCount) day streak")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.heatmapDays.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "calendar",
                    description: Text("Record entries to build your streak.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                HeatmapGridView(days: viewModel.heatmapDays)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .accessibilityLabel("Streak heatmap")
            }
        }
    }

    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On This Day")
                .font(.headline)

            if viewModel.onThisDayEntries.isEmpty {
                ContentUnavailableView(
                    "No past entries",
                    systemImage: "sparkles",
                    description: Text("Check back after a few weeks.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.onThisDayEntries, id: \.id) { entry in
                        NavigationLink {
                            JournalEntryDetailView(entry: entry)
                        } label: {
                            OnThisDayRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens entry details.")
                    }
                }
            }
        }
    }

    private var weeklySummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Summary")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isLoadingSummary {
                    ProgressView("Generating summary...")
                        .progressViewStyle(.circular)
                } else if let summaryError = viewModel.summaryError {
                    Text(summaryError)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Try Again") {
                        HapticManager.shared.selection()
                        Task {
                            await viewModel.load(
                                using: modelContext,
                                includeSummary: subscriptionService.hasInsights
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Regenerates the weekly summary.")
                } else {
                    Text(
                        viewModel.weeklySummary.isEmpty
                            ? "No summary available yet." : viewModel.weeklySummary
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .accessibilityLabel("Weekly summary")
        }
    }

    private var lockedWeeklySummarySection: some View {
        lockedSection(title: "Weekly Summary") {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                Text("Your weekly summary")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .lockedFeatureOverlay(isLocked: true, feature: "insights_weekly_summary")
    }

    private var monthlyTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Trends")
                .font(.headline)

            Chart(viewModel.monthlyTrends) { item in
                BarMark(
                    x: .value("Month", item.month, unit: .month),
                    y: .value("Entries", item.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 200)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .accessibilityLabel("Monthly trends chart")
        }
    }

    private var lockedMonthlyTrendsSection: some View {
        lockedSection(title: "Monthly Trends") {
            LockedChartPlaceholder(height: 200)
        }
        .lockedFeatureOverlay(isLocked: true, feature: "insights_monthly_trends")
    }

    private func lockedSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
                    await viewModel.load(
                        using: modelContext,
                        includeSummary: subscriptionService.hasInsights
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Reloads insights.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct StatCardView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Spacer()
            }

            Text(value.isEmpty ? "--" : value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value.isEmpty ? "--" : value)")
    }
}

private struct HeatmapGridView: View {
    let days: [InsightsViewModel.HeatmapDay]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let maxCount = max(days.map(\.count).max() ?? 1, 1)

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days) { day in
                HeatmapCell(day: day, maxCount: maxCount)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HeatmapCell: View {
    let day: InsightsViewModel.HeatmapDay
    let maxCount: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(cellStyle)
            .frame(height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(day.isInStreak ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 1)
            )
            .accessibilityLabel(accessibilityText)
    }

    private var cellStyle: AnyShapeStyle {
        guard day.count > 0 else {
            return AnyShapeStyle(Color(.systemFill).opacity(0.2))
        }
        let intensity = min(1, Double(day.count) / Double(maxCount))
        let start = 0.15 + (0.15 * intensity)
        let end = 0.3 + (0.35 * intensity)
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(start),
                    Color.accentColor.opacity(end),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var accessibilityText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: day.date)), \(day.count) entries"
    }
}

private struct OnThisDayRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(entry.title.trimmed.isEmpty ? entry.firstLineFallback : entry.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Spacer()

            if entry.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct PreviewChip: View {
    let text: String

    var body: some View {
        Text(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color(.systemFill))
            )
    }
}

private struct LockedChartPlaceholder: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemFill))
            .frame(height: height)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.25),
                        Color.accentColor.opacity(0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .redacted(reason: .placeholder)
            .blur(radius: 3)
    }
}

private struct InsightsSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 24) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonStatCard()
                }
            }

            SkeletonChartCard(titleWidth: 120)
            SkeletonChartCard(titleWidth: 140)
            SkeletonChartCard(titleWidth: 160)
            SkeletonSummaryCard()
        }
    }
}

private struct SkeletonStatCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonLine(width: 20, height: 12)
            SkeletonLine(width: 80, height: 16)
            SkeletonLine(width: 100, height: 10)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .redacted(reason: .placeholder)
        .shimmer()
    }
}

private struct SkeletonChartCard: View {
    let titleWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(width: titleWidth, height: 12)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemFill))
                .frame(height: 200)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .redacted(reason: .placeholder)
        .shimmer()
    }
}

private struct SkeletonSummaryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonLine(width: 140, height: 12)
            SkeletonLine(width: 220, height: 10)
            SkeletonLine(width: 180, height: 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .redacted(reason: .placeholder)
        .shimmer()
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension JournalEntry {
    fileprivate var firstLineFallback: String {
        let line = transcription.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: JournalEntry.self, Tag.self, configurations: config)
    let context = container.mainContext
    let calendar = Calendar.current

    for offset in 0..<12 {
        if let date = calendar.date(byAdding: .day, value: -offset, to: Date()) {
            let entry = JournalEntry(
                title: "Entry \(offset + 1)",
                createdAt: date,
                transcription: "Sample transcription for insights view.",
                duration: TimeInterval(120 + offset * 30),
                mood: Mood.allCases[offset % Mood.allCases.count],
                tags: ["Work", "Reflection"],
                isFavorite: offset % 4 == 0
            )
            context.insert(entry)
        }
    }

    return InsightsView()
        .modelContainer(container)
        .environmentObject(SubscriptionService())
}
#endif
