import SwiftUI

struct HomeEntryCardView: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.createdAt.journalFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if entry.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                }
            }

            Text(headlineText)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)

            if entry.duration > 0 || !entry.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if entry.duration > 0 {
                        Label(durationText, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !entry.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(entry.tags, id: \.self) { tag in
                                TagPillView(name: tag)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.2))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var headlineText: String {
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let trimmedTranscription = entry.transcription.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if !trimmedTranscription.isEmpty {
            return
                trimmedTranscription
                .split(whereSeparator: \.isNewline)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? "Untitled Entry"
        }

        return "Untitled Entry"
    }

    private var durationText: String {
        let minutes = Int(entry.duration) / 60
        let seconds = Int(entry.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var accessibilityText: String {
        var parts: [String] = [
            entry.createdAt.formatted(date: .abbreviated, time: .shortened),
            headlineText,
        ]

        if entry.duration > 0 {
            parts.append("Duration \(durationText)")
        }

        if !entry.tags.isEmpty {
            parts.append("Tags \(entry.tags.joined(separator: ", "))")
        }

        if entry.isFavorite {
            parts.append("Favorite")
        }

        return parts.joined(separator: ", ")
    }
}

private struct TagPillView: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    let entry = JournalEntry(
        title: "Morning Reflection",
        transcription: "First line of transcription.\nSecond line continues the story.",
        duration: 92,
        tags: ["Personal", "Mindfulness"],
        isFavorite: true
    )

    return HomeEntryCardView(entry: entry)
        .padding()
}
#endif
