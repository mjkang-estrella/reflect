import SwiftUI

struct WaveformView: View {
    let audioLevels: [Float]
    let isRecording: Bool
    let barCount: Int
    let barSpacing: CGFloat
    let minBarHeight: CGFloat
    let maxBarHeight: CGFloat
    let barColor: Color
    let animationDuration: Double

    init(
        audioLevels: [Float],
        isRecording: Bool = true,
        barCount: Int = 40,
        barSpacing: CGFloat = 3,
        minBarHeight: CGFloat = 4,
        maxBarHeight: CGFloat = 60,
        barColor: Color = .accentColor,
        animationDuration: Double = 0.1
    ) {
        self.audioLevels = audioLevels
        self.isRecording = isRecording
        self.barCount = barCount
        self.barSpacing = barSpacing
        self.minBarHeight = minBarHeight
        self.maxBarHeight = maxBarHeight
        self.barColor = barColor
        self.animationDuration = animationDuration
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        level: levelForIndex(index),
                        isRecording: isRecording,
                        minHeight: minBarHeight,
                        maxHeight: maxBarHeight,
                        color: barColor,
                        animationDuration: animationDuration
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func levelForIndex(_ index: Int) -> Float {
        guard !audioLevels.isEmpty else {
            return isRecording ? Float.random(in: 0.05...0.15) : 0.05
        }

        // Map bar index to audio level array
        let audioIndex = Int(Float(index) / Float(barCount) * Float(audioLevels.count))
        let clampedIndex = min(max(0, audioIndex), audioLevels.count - 1)

        return audioLevels[clampedIndex]
    }
}

// MARK: - Waveform Bar

struct WaveformBar: View {
    let level: Float
    let isRecording: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let color: Color
    let animationDuration: Double

    @State private var animatedLevel: Float = 0

    private var barHeight: CGFloat {
        let normalizedLevel = CGFloat(animatedLevel)
        return minHeight + (maxHeight - minHeight) * normalizedLevel
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(isRecording ? 0.8 + Double(animatedLevel) * 0.2 : 0.3))
            .frame(width: 4, height: barHeight)
            .animation(.easeOut(duration: animationDuration), value: animatedLevel)
            .onChange(of: level) { _, newValue in
                animatedLevel = newValue
            }
            .onAppear {
                animatedLevel = level
            }
    }
}

// MARK: - Live Waveform View (Animated when idle)

struct LiveWaveformView: View {
    let audioLevels: [Float]
    let isRecording: Bool
    let isPaused: Bool

    @State private var idlePhase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            WaveformCanvas(
                audioLevels: audioLevels,
                isRecording: isRecording,
                isPaused: isPaused,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
        }
    }
}

// MARK: - Waveform Canvas (High-performance drawing)

struct WaveformCanvas: View {
    let audioLevels: [Float]
    let isRecording: Bool
    let isPaused: Bool
    let time: TimeInterval

    private let barCount = 50
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 8
    private let maxBarHeight: CGFloat = 80

    var body: some View {
        Canvas { context, size in
            let totalSpacing = CGFloat(barCount - 1) * barSpacing
            let barWidth = (size.width - totalSpacing) / CGFloat(barCount)
            let centerY = size.height / 2

            for i in 0..<barCount {
                let level = levelForIndex(i)
                let barHeight = minBarHeight + (maxBarHeight - minBarHeight) * CGFloat(level)

                let x = CGFloat(i) * (barWidth + barSpacing)
                let y = centerY - barHeight / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: barWidth / 2)
                    .path(in: rect)

                let opacity = isRecording ? 0.6 + Double(level) * 0.4 : (isPaused ? 0.4 : 0.2)
                context.fill(path, with: .color(.accentColor.opacity(opacity)))
            }
        }
    }

    private func levelForIndex(_ index: Int) -> Float {
        if isRecording && !audioLevels.isEmpty {
            let audioIndex = Int(Float(index) / Float(barCount) * Float(audioLevels.count))
            let clampedIndex = min(max(0, audioIndex), audioLevels.count - 1)
            return audioLevels[clampedIndex]
        } else if isPaused {
            // Static wave when paused
            let position = Float(index) / Float(barCount)
            return 0.2 + 0.1 * sin(position * .pi * 4)
        } else {
            // Gentle idle animation
            let position = Float(index) / Float(barCount)
            let phase = Float(time * 2)
            return 0.15 + 0.1 * sin(position * .pi * 3 + phase)
        }
    }
}

// MARK: - Circular Waveform View

struct CircularWaveformView: View {
    let audioLevels: [Float]
    let isRecording: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
            CircularWaveformCanvas(
                audioLevels: audioLevels,
                isRecording: isRecording,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
        }
    }
}

private struct CircularWaveformCanvas: View {
    let audioLevels: [Float]
    let isRecording: Bool
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            drawWaveform(in: &context, size: size)
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = min(size.width, size.height) / 2 - 30
        let barCount = 60

        for i in 0..<barCount {
            let angle = (Double(i) / Double(barCount)) * 2 * .pi - .pi / 2
            let level = levelForIndex(i)

            let innerRadius = baseRadius - 5
            let outerRadius = baseRadius + CGFloat(level) * 25
            let cosAngle = CGFloat(cos(angle))
            let sinAngle = CGFloat(sin(angle))

            let innerPoint = CGPoint(
                x: center.x + innerRadius * cosAngle,
                y: center.y + innerRadius * sinAngle
            )
            let outerPoint = CGPoint(
                x: center.x + outerRadius * cosAngle,
                y: center.y + outerRadius * sinAngle
            )

            var path = Path()
            path.move(to: innerPoint)
            path.addLine(to: outerPoint)

            let opacity = isRecording ? 0.5 + Double(level) * 0.5 : 0.3
            context.stroke(
                path,
                with: .color(.accentColor.opacity(opacity)),
                lineWidth: 3
            )
        }
    }

    private func levelForIndex(_ index: Int) -> Float {
        if isRecording && !audioLevels.isEmpty {
            let audioIndex = Int(Float(index) / 60.0 * Float(audioLevels.count))
            let clampedIndex = min(max(0, audioIndex), audioLevels.count - 1)
            return audioLevels[clampedIndex]
        } else {
            let position = Float(index) / 60.0
            let phase = Float(time * 1.5)
            return 0.2 + 0.15 * sin(position * .pi * 4 + phase)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    VStack(spacing: 40) {
        LiveWaveformView(
            audioLevels: (0..<50).map { _ in Float.random(in: 0.1...0.8) },
            isRecording: true,
            isPaused: false
        )
        .frame(height: 100)

        LiveWaveformView(
            audioLevels: [],
            isRecording: false,
            isPaused: false
        )
        .frame(height: 100)

        CircularWaveformView(
            audioLevels: (0..<50).map { _ in Float.random(in: 0.1...0.8) },
            isRecording: true
        )
        .frame(width: 200, height: 200)
    }
    .padding()
}
#endif
