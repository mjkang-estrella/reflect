import AVFoundation
import Combine
import SwiftUI

struct JournalSummaryView: View {
    let entry: JournalEntry
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = JournalSummaryViewModel()
    @StateObject private var audioPlayer = AudioPlaybackModel()
    @State private var isTranscriptExpanded = false
    @State private var isDeleteConfirmationShown = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ZStack {
            AppGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(entryTitle)
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundColor(Color(hex: 0x101828))

                    if shouldShowAudio {
                        audioCard
                    }

                    transcriptCard

                    summarySection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(onClose != nil)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isDeleteConfirmationShown = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red.opacity(0.9))
                }
                .disabled(isDeleting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let onClose {
                Button("Done") {
                    onClose()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: 0x101828))
                )
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
            }
        }
        .alert("Delete entry?", isPresented: $isDeleteConfirmationShown) {
            Button("Delete", role: .destructive) {
                Task { await deleteEntry() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the transcript, summary, and audio file.")
        }
        .alert(
            "Delete failed",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                deleteError = nil
            }
        } message: {
            Text(deleteError ?? "Unable to delete entry.")
        }
        .task(id: entry.id) {
            await viewModel.load(entry: entry)
            if let audioURL = viewModel.audioURL {
                audioPlayer.load(url: audioURL)
            }
        }
        .onChange(of: viewModel.audioURL) { newValue in
            if let newValue {
                audioPlayer.load(url: newValue)
            }
        }
    }

    private var entryTitle: String {
        if let summaryHeadline = viewModel.summary?.headline.trimmingCharacters(in: .whitespacesAndNewlines),
           !summaryHeadline.isEmpty {
            return summaryHeadline
        }
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return Self.titleFallbackFormatter.string(from: entry.createdAt)
    }

    private var shouldShowAudio: Bool {
        entry.audioUrl != nil || viewModel.audioError != nil
    }

    private var audioCard: some View {
        HStack(spacing: 12) {
            Button(action: audioPlayer.togglePlayback) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x101828))
                        .frame(width: 40, height: 40)

                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.leading, audioPlayer.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioURL == nil)

            WaveformView(
                bars: WaveformView.defaultBars,
                progress: audioPlayer.progress
            )
            .frame(height: 32)

            Text(audioDurationText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: 0x6A7282))

            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: 0x6A7282))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        )
        .overlay(alignment: .bottomLeading) {
            if let audioError = viewModel.audioError {
                Text(audioError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: 0xB42318))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    private var audioDurationText: String {
        let preferred = entry.duration > 0 ? entry.duration : audioPlayer.duration
        return TimeFormatter.mmss(preferred)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if trimmedTranscript.isEmpty {
                Text("No transcription yet.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x6A7282))
            } else {
                if let leadLine {
                    Text(leadLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: 0x6A7282))
                }

                if !transcriptionBody.isEmpty {
                    Text(transcriptionBody)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0x364153))
                        .lineSpacing(6)
                        .lineLimit(isTranscriptExpanded ? nil : 3)

                    if transcriptionBody.count > 140 {
                        Button(isTranscriptExpanded ? "Show less" : "Show more") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTranscriptExpanded.toggle()
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: 0x101828))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.4))
        )
    }

    private var trimmedTranscript: String {
        entry.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var leadLine: String? {
        let lines = transcriptLines
        guard let first = lines.first else { return nil }
        return String(first)
    }

    private var transcriptionBody: String {
        let lines = transcriptLines
        if lines.count <= 1 {
            return ""
        }
        return lines.dropFirst().joined(separator: " ")
    }

    private var transcriptLines: [Substring] {
        entry.transcription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0xFAF5FF))
                        .frame(width: 28, height: 28)

                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0x6E11B0))
                }

                Text("AI SUMMARY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x6E11B0))
                    .tracking(0.6)
            }

            if viewModel.isLoadingSummary {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(hex: 0x6E11B0))
            } else if let summary = viewModel.summary {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color(hex: 0x6E11B0))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            Text(bullet)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: 0x1E2939))
                        }
                    }
                }
            } else if let error = viewModel.summaryError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xB42318))

                Button("Retry summary") {
                    Task { await viewModel.retrySummary(entry: entry) }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: 0x101828))
                .buttonStyle(.plain)
            } else {
                Text("Summary will appear here soon.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x6A7282))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        )
    }

    private func deleteEntry() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            if let audioPath = entry.audioUrl, !audioPath.isEmpty {
                let storage = try AudioStorageService()
                try await storage.deleteAudio(pathOrUrl: audioPath)
            }

            let repository = try JournalRepository()
            try await repository.deleteSession(sessionId: entry.id)
            NotificationCenter.default.post(name: .journalEntriesDidChange, object: nil)

            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

@MainActor
final class JournalSummaryViewModel: ObservableObject {
    @Published var summary: SummaryPayload?
    @Published var isLoadingSummary = false
    @Published var summaryError: String?
    @Published var audioURL: URL?
    @Published var audioError: String?

    private var loadedEntryId: UUID?

    func load(entry: JournalEntry) async {
        guard loadedEntryId != entry.id else { return }
        loadedEntryId = entry.id

        await loadSummary(entry: entry)
        await loadAudio(entry: entry)
    }

    func retrySummary(entry: JournalEntry) async {
        summaryError = nil
        summary = nil
        await loadSummary(entry: entry)
    }

    private func loadSummary(entry: JournalEntry) async {
        guard !entry.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            summaryError = "No transcript to summarize yet."
            return
        }

        if let cached = entry.summary {
            summary = cached
            summaryError = nil
            return
        }

        guard !isLoadingSummary else { return }
        isLoadingSummary = true
        defer { isLoadingSummary = false }

        do {
            let repository = try JournalRepository()
            if let stored = try await repository.fetchSummary(sessionId: entry.id) {
                summary = stored
                summaryError = nil
                return
            }
        } catch {
            summaryError = "Unable to fetch existing summary."
        }

        do {
            let service = try SummaryService()
            let generated = try await service.generateSummary(
                sessionId: entry.id,
                transcript: entry.transcription,
                title: entry.title
            )
            summary = generated
            summaryError = nil
        } catch {
            summaryError = "Summary generation failed."
        }
    }

    private func loadAudio(entry: JournalEntry) async {
        audioURL = nil
        audioError = nil
        guard let audioPath = entry.audioUrl, !audioPath.isEmpty else { return }

        do {
            audioError = nil
            let storage = try AudioStorageService()
            audioURL = try await storage.signedURL(for: audioPath, expiresIn: 3600)
        } catch {
            audioError = "Audio unavailable."
        }
    }
}

final class AudioPlaybackModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    deinit {
        cleanup()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func load(url: URL) {
        cleanup()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        addTimeObserver()
        addEndObserver(for: item)
        Task { await loadDuration(for: item) }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func loadDuration(for item: AVPlayerItem) async {
        do {
            let durationValue = try await item.asset.load(.duration)
            let seconds = CMTimeGetSeconds(durationValue)
            if seconds.isFinite {
                await MainActor.run { self.duration = seconds }
            }
        } catch {
            await MainActor.run { self.duration = 0 }
        }
    }

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
        }
    }

    private func addEndObserver(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.player?.seek(to: .zero)
        }
    }

    private func cleanup() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        endObserver = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}

struct WaveformView: View {
    let bars: [CGFloat]
    let progress: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(bars.indices, id: \.self) { index in
                let ratio = Double(index + 1) / Double(bars.count)
                let isActive = ratio <= progress
                Capsule()
                    .fill(Color(hex: 0x101828).opacity(isActive ? 1.0 : 0.2))
                    .frame(width: 3, height: bars[index])
            }
        }
    }

    static let defaultBars: [CGFloat] = [
        6, 16, 30, 32, 29, 8, 16, 6, 19, 6,
        10, 25, 15, 8, 28, 30, 22, 6, 6, 6,
        24, 6, 30, 29, 11, 25, 16, 6, 6, 10,
        9, 14, 12, 20, 31, 7, 8, 6, 18, 11
    ]
}

private extension JournalSummaryView {
    static let titleFallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()
}

enum TimeFormatter {
    static func mmss(_ duration: Double) -> String {
        guard duration.isFinite, duration > 0 else { return "0:00" }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        JournalSummaryView(entry: JournalEntry.sampleEntries[1], onClose: nil)
    }
#endif
