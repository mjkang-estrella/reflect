import SwiftUI

struct EmptyStateView: View {
    var onRecordTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: 8) {
                Text("Your journal starts here")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Record your thoughts, feelings, and daily moments. Your voice journal will help you reflect and grow.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // CTA Button
            if let onRecordTap = onRecordTap {
                Button(action: {
                    HapticManager.shared.impact(.medium)
                    onRecordTap()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                        Text("Record your first entry")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }

            // Tips
            VStack(alignment: .leading, spacing: 12) {
                EmptyStateTip(
                    icon: "lightbulb.fill",
                    text: "Speak freely - AI transcribes everything"
                )
                EmptyStateTip(
                    icon: "face.smiling",
                    text: "Track your mood over time"
                )
                EmptyStateTip(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "See insights from your journaling"
                )
            }
            .padding(.top, 16)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty State Tip

struct EmptyStateTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Calendar Empty State

struct CalendarEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Start your streak today")
                .font(.headline)

            Text("Record an entry to see it appear on your calendar. Keep journaling daily to build your streak!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
    }
}

// MARK: - Insights Empty State

struct InsightsEmptyStateView: View {
    let entryCount: Int
    let requiredCount: Int

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(entryCount) / CGFloat(requiredCount))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(entryCount)")
                        .font(.title2.bold())
                    Text("of \(requiredCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Keep going!")
                .font(.headline)

            Text("Journal for \(requiredCount - entryCount) more day\(requiredCount - entryCount == 1 ? "" : "s") to unlock your first insights.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview("Home Empty State") {
    EmptyStateView() {
        print("Record tapped")
    }
    .padding()
}

#Preview("Calendar Empty State") {
    CalendarEmptyStateView()
        .padding()
}

#Preview("Insights Empty State") {
    InsightsEmptyStateView(entryCount: 1, requiredCount: 3)
        .padding()
}
#endif
