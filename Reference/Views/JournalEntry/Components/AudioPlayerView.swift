import SwiftUI

struct AudioPlayerView: View {
    @ObservedObject var playerService: AudioPlayerService
    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            progressSection

            // Time labels
            timeLabels

            // Playback controls
            playbackControls
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray4))
                    .frame(height: 8)

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: progressWidth(in: geometry.size.width), height: 8)

                // Scrubber handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .offset(x: scrubberOffset(in: geometry.size.width))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                    }
                    .onEnded { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        playerService.seek(toProgress: progress)
                        isDragging = false
                        HapticManager.shared.selection()
                    }
            )
        }
        .frame(height: 20)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let progress = isDragging ? dragProgress : playerService.progress
        return totalWidth * CGFloat(progress)
    }

    private func scrubberOffset(in totalWidth: CGFloat) -> CGFloat {
        let progress = isDragging ? dragProgress : playerService.progress
        let offset = totalWidth * CGFloat(progress) - 10
        return max(-10, min(offset, totalWidth - 10))
    }

    // MARK: - Time Labels

    private var timeLabels: some View {
        HStack {
            Text(playerService.formattedCurrentTime)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Spacer()

            Text("-\(playerService.formattedRemainingTime)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 32) {
            // Playback rate button
            Button(action: {
                playerService.cyclePlaybackRate()
            }) {
                Text(playerService.playbackRateDisplay)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }

            // Skip backward
            Button(action: {
                playerService.skipBackward()
                HapticManager.shared.impact(.light)
            }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
            }

            // Play/Pause button
            Button(action: {
                playerService.togglePlayPause()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 56, height: 56)

                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .offset(x: playerService.isPlaying ? 0 : 2)
                }
            }
            .disabled(playerService.state == .loading || playerService.state == .error(""))

            // Skip forward
            Button(action: {
                playerService.skipForward()
                HapticManager.shared.impact(.light)
            }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
            }

            // Spacer for symmetry
            Color.clear
                .frame(width: 44, height: 32)
        }
    }
}

// MARK: - Compact Audio Player

struct CompactAudioPlayerView: View {
    @ObservedObject var playerService: AudioPlayerService

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: {
                playerService.togglePlayPause()
            }) {
                Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray4))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(playerService.progress), height: 4)
                    }
                }
                .frame(height: 4)

                // Time
                Text("\(playerService.formattedCurrentTime) / \(playerService.formattedDuration)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Waveform Audio Player

struct WaveformAudioPlayerView: View {
    @ObservedObject var playerService: AudioPlayerService
    let waveformData: [Float]

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            // Waveform with progress
            GeometryReader { geometry in
                ZStack {
                    // Background waveform
                    WaveformShape(levels: waveformData)
                        .fill(Color(.systemGray4))

                    // Progress waveform
                    WaveformShape(levels: waveformData)
                        .fill(Color.accentColor)
                        .mask(
                            Rectangle()
                                .frame(width: geometry.size.width * currentProgress)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragProgress = max(0, min(1, value.location.x / geometry.size.width))
                        }
                        .onEnded { _ in
                            playerService.seek(toProgress: dragProgress)
                            isDragging = false
                        }
                )
            }
            .frame(height: 60)

            // Controls
            HStack {
                Text(playerService.formattedCurrentTime)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { playerService.togglePlayPause() }) {
                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }

                Spacer()

                Text(playerService.formattedDuration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    private var currentProgress: Double {
        isDragging ? dragProgress : playerService.progress
    }
}

// MARK: - Waveform Shape

struct WaveformShape: Shape {
    let levels: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !levels.isEmpty else { return path }

        let barWidth = rect.width / CGFloat(levels.count)
        let maxHeight = rect.height / 2

        for (index, level) in levels.enumerated() {
            let barHeight = maxHeight * CGFloat(level)
            let x = CGFloat(index) * barWidth
            let y = rect.midY - barHeight

            let barRect = CGRect(x: x, y: y, width: barWidth - 1, height: barHeight * 2)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: 1, height: 1))
        }

        return path
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    VStack(spacing: 20) {
        AudioPlayerView(playerService: AudioPlayerService())

        CompactAudioPlayerView(playerService: AudioPlayerService())

        WaveformAudioPlayerView(
            playerService: AudioPlayerService(),
            waveformData: (0..<50).map { _ in Float.random(in: 0.2...1.0) }
        )
    }
    .padding()
}
#endif
