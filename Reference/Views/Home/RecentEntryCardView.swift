import SwiftUI

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

        let trimmedTranscription = entry.transcription.trimmingCharacters(
            in: .whitespacesAndNewlines)
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

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    let entry = JournalEntry(
        title: "On the way home",
        transcription: "I keep thinking about that conversation from today. I don't think I said what I meant.",
        duration: 0,
        tags: ["Thoughts"],
        isFavorite: false
    )

    return RecentEntryCardView(entry: entry)
        .padding()
        .background(Color.black)
}
#endif
