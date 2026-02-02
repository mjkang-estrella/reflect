import SwiftData
import SwiftUI
import UIKit

struct JournalEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var fileCleanupService: FileCleanupService

    @Bindable var entry: JournalEntry

    @StateObject private var playerService = AudioPlayerService()

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedTranscription: String = ""
    @State private var editedTags: [String] = []
    @State private var editedMood: Mood?

    @State private var showingMoodPicker = false
    @State private var showingTagPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var showingPaywall = false
    @State private var paywallSource = "export_pdf"

    var onDelete: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                headerSection

                // Audio player
                if entry.audioFilePath != nil {
                    audioPlayerSection
                }

                // Metadata section (date, duration, mood)
                metadataSection

                // Tags section
                tagsSection

                // Transcription section
                transcriptionSection

                // Delete button
                deleteSection
            }
            .padding()
        }
        .navigationTitle(isEditing ? "Edit Entry" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isEditing {
                        Button("Cancel") {
                            cancelEditing()
                        }

                        Button("Save") {
                            saveChanges()
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button(action: { showingShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }

                        Button(action: { startEditing() }) {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingMoodPicker) {
            MoodPickerView(
                selectedMood: isEditing
                    ? $editedMood
                    : Binding(
                        get: { entry.mood },
                        set: { entry.mood = $0 }
                    ))
        }
        .sheet(isPresented: $showingTagPicker) {
            tagPickerSheet
        }
        .sheet(isPresented: $showingShareSheet) {
            shareSheet
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: paywallSource)
                .environmentObject(subscriptionService)
        }
        .alert("Delete Entry?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
        } message: {
            Text(
                "This will permanently delete this journal entry and its audio recording. This action cannot be undone."
            )
        }
        .task {
            await loadAudio()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                TextField("Entry Title", text: $editedTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .textFieldStyle(.plain)
            } else {
                Text(entry.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Favorite button
            HStack {
                Button(action: { toggleFavorite() }) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(entry.isFavorite ? .red : .secondary)

                        Text(entry.isFavorite ? "Favorited" : "Add to Favorites")
                            .font(.subheadline)
                            .foregroundColor(entry.isFavorite ? .red : .secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
        }
    }

    // MARK: - Audio Player Section

    private var audioPlayerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                Text("Audio Recording")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            AudioPlayerView(playerService: playerService)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Date
                MetadataItem(
                    icon: "calendar",
                    title: "Date",
                    value: entry.createdAt.formatted(date: .abbreviated, time: .shortened)
                )

                // Duration
                if entry.duration > 0 {
                    MetadataItem(
                        icon: "clock",
                        title: "Duration",
                        value: formatDuration(entry.duration)
                    )
                }
            }

            // Mood - Inline picker for quick selection
            moodSection
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.accentColor)
                Text("Mood")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                // Current mood display
                if let currentMood = isEditing ? editedMood : entry.mood {
                    Text(currentMood.displayName)
                        .font(.caption)
                        .foregroundColor(currentMood.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(currentMood.color.opacity(0.15))
                        )
                }
            }

            // Inline horizontal mood picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        InlineMoodButton(
                            mood: mood,
                            isSelected: (isEditing ? editedMood : entry.mood) == mood
                        ) {
                            HapticManager.shared.impact(.light)
                            if isEditing {
                                editedMood = editedMood == mood ? nil : mood
                            } else {
                                entry.mood = entry.mood == mood ? nil : mood
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { showingTagPicker = true }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
            }

            let displayTags = isEditing ? editedTags : entry.tags

            if displayTags.isEmpty {
                Text("No tags added")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(displayTags, id: \.self) { tag in
                        TagChip(
                            name: tag,
                            color: .accentColor,
                            isSelected: isEditing
                        ) {
                            if isEditing {
                                editedTags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var tagPickerSheet: some View {
        NavigationStack {
            TagPickerView(
                selectedTags: isEditing
                    ? $editedTags
                    : Binding(
                        get: { entry.tags },
                        set: { entry.tags = $0 }
                    )
            )
            .padding()
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingTagPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundColor(.accentColor)
                Text("Transcription")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            if isEditing {
                TextEditor(text: $editedTranscription)
                    .font(.body)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
            } else {
                if entry.transcription.isEmpty {
                    Text("No transcription available")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                } else {
                    Text(entry.transcription)
                        .font(.body)
                        .lineSpacing(6)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button(action: { showingDeleteConfirmation = true }) {
            HStack {
                Image(systemName: "trash")
                Text("Delete Entry")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 20)
    }

    // MARK: - Share Sheet

    private var shareSheet: some View {
        NavigationStack {
            List {
                Section("Export") {
                    Button(action: { shareAsText() }) {
                        Label("Export as Text", systemImage: "doc.text")
                    }

                    Button {
                        if subscriptionService.hasExportPDF {
                            shareAsPDF()
                        } else {
                            AnalyticsService.track(
                                .premiumFeatureBlocked(feature: FeatureType.export.rawValue)
                            )
                            showingShareSheet = false
                            paywallSource = "export_pdf"
                            showingPaywall = true
                        }
                    } label: {
                        HStack {
                            Label("Export as PDF", systemImage: "doc.richtext")
                            Spacer()
                            if !subscriptionService.hasExportPDF {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Share") {
                    if entry.audioFilePath != nil {
                        Button(action: { shareAsAudio() }) {
                            Label("Audio File", systemImage: "waveform")
                        }
                    }

                    Button(action: { shareAsBoth() }) {
                        Label("Text & Audio", systemImage: "doc.on.doc")
                    }
                    .disabled(entry.audioFilePath == nil)
                }
            }
            .navigationTitle("Share Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingShareSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func loadAudio() async {
        if let audioPath = entry.audioFilePath {
            await playerService.loadAudio(fileName: audioPath)
        }
    }

    private func toggleFavorite() {
        entry.isFavorite.toggle()
        HapticManager.shared.impact(.light)
    }

    private func startEditing() {
        editedTitle = entry.title
        editedTranscription = entry.transcription
        editedTags = entry.tags
        editedMood = entry.mood
        isEditing = true
        HapticManager.shared.impact(.light)
    }

    private func cancelEditing() {
        isEditing = false
        HapticManager.shared.impact(.light)
    }

    private func saveChanges() {
        entry.title = editedTitle
        entry.transcription = editedTranscription
        entry.tags = editedTags
        entry.mood = editedMood

        isEditing = false
        HapticManager.shared.notification(.success)
    }

    private func deleteEntry() {
        // Delete audio file using FileCleanupService
        fileCleanupService.deleteAudioFile(for: entry)

        // Track analytics
        AnalyticsService.track(
            .entryDeleted(
                hadAudio: entry.audioFilePath != nil,
                duration: entry.duration
            ))

        modelContext.delete(entry)
        HapticManager.shared.notification(.success)
        onDelete?()
        dismiss()
    }

    private func shareAsText() {
        let text = generateShareText()
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        presentActivityController(activityVC)
        showingShareSheet = false
    }

    private func shareAsAudio() {
        guard let audioPath = entry.audioFilePath else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
            0]
        let recordingsDir = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        let fileURL = recordingsDir.appendingPathComponent(audioPath)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let activityVC = UIActivityViewController(
                activityItems: [fileURL], applicationActivities: nil)
            presentActivityController(activityVC)
        }
        showingShareSheet = false
    }

    private func shareAsBoth() {
        var items: [Any] = [generateShareText()]

        if let audioPath = entry.audioFilePath {
            let documentsPath = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsDir = documentsPath.appendingPathComponent(
                "Recordings", isDirectory: true)
            let fileURL = recordingsDir.appendingPathComponent(audioPath)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                items.append(fileURL)
            }
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        presentActivityController(activityVC)
        showingShareSheet = false
    }

    private func shareAsPDF() {
        let data = generatePDFData()
        let filename = "VoiceJournal-\(entry.id).pdf"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: .atomic)
            let activityVC = UIActivityViewController(
                activityItems: [fileURL], applicationActivities: nil)
            presentActivityController(activityVC)
        } catch {
            // Best effort; ignore failures.
        }

        showingShareSheet = false
    }

    private func generateShareText() -> String {
        var text = """
            \(entry.displayTitle)
            \(entry.createdAt.formatted(date: .long, time: .shortened))
            """

        if let mood = entry.mood {
            text += "\nMood: \(mood.emoji) \(mood.displayName)"
        }

        if !entry.tags.isEmpty {
            text += "\nTags: \(entry.tags.joined(separator: ", "))"
        }

        if !entry.transcription.isEmpty {
            text += "\n\n\(entry.transcription)"
        }

        text += "\n\n— Recorded with VoiceJournal"

        return text
    }

    private func generatePDFData() -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let titleFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let secondaryFont = UIFont.systemFont(ofSize: 11)

        return renderer.pdfData { context in
            context.beginPage()
            var yOffset: CGFloat = 40

            let title = entry.displayTitle
            let titleRect = CGRect(x: 40, y: yOffset, width: pageBounds.width - 80, height: 28)
            title.draw(in: titleRect, withAttributes: [.font: titleFont])
            yOffset += 32

            let dateString = entry.createdAt.formatted(date: .long, time: .shortened)
            let meta = "Recorded \(dateString)"
            let metaRect = CGRect(x: 40, y: yOffset, width: pageBounds.width - 80, height: 18)
            meta.draw(
                in: metaRect,
                withAttributes: [.font: secondaryFont, .foregroundColor: UIColor.secondaryLabel])
            yOffset += 24

            if let mood = entry.mood {
                let moodText = "Mood: \(mood.emoji) \(mood.displayName)"
                let moodRect = CGRect(x: 40, y: yOffset, width: pageBounds.width - 80, height: 18)
                moodText.draw(
                    in: moodRect,
                    withAttributes: [
                        .font: secondaryFont, .foregroundColor: UIColor.secondaryLabel,
                    ])
                yOffset += 20
            }

            if !entry.tags.isEmpty {
                let tagsText = "Tags: \(entry.tags.joined(separator: ", "))"
                let tagsRect = CGRect(x: 40, y: yOffset, width: pageBounds.width - 80, height: 18)
                tagsText.draw(
                    in: tagsRect,
                    withAttributes: [
                        .font: secondaryFont, .foregroundColor: UIColor.secondaryLabel,
                    ])
                yOffset += 24
            }

            let body =
                entry.transcription.isEmpty ? "No transcription available." : entry.transcription
            let bodyRect = CGRect(
                x: 40,
                y: yOffset,
                width: pageBounds.width - 80,
                height: pageBounds.height - yOffset - 40
            )
            body.draw(in: bodyRect, withAttributes: [.font: bodyFont])
        }
    }

    private func presentActivityController(_ activityVC: UIActivityViewController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootVC = windowScene.windows.first?.rootViewController
        {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Metadata Item

struct MetadataItem: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: JournalEntry.self, Tag.self, configurations: config)

        let entry = JournalEntry(
            title: "My First Entry",
            transcription:
                "This is a sample transcription of my voice journal entry. I'm testing out the detail view to see how everything looks. The transcription should wrap nicely and be easy to read.",
            duration: 125,
            mood: .happy,
            tags: ["Personal", "Reflection"]
        )
        container.mainContext.insert(entry)

        return NavigationStack {
            JournalEntryDetailView(entry: entry)
        }
        .modelContainer(container)
        .environmentObject(SubscriptionService())
        .environmentObject(FileCleanupService())
    }
#endif
