import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let isPaused: Bool
    let isProcessing: Bool
    let audioLevel: Float
    let action: () -> Void

    @State private var isPressing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var ringRotation: Double = 0

    private let buttonSize: CGFloat = 80
    private let ringSize: CGFloat = 100

    var body: some View {
        ZStack {
            // Outer animated ring
            if isRecording || isPaused {
                recordingRing
            }

            // Pulsing background when recording
            if isRecording {
                pulsingBackground
            }

            // Main button
            mainButton
        }
        .frame(width: ringSize + 20, height: ringSize + 20)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startPulseAnimation()
                startRingAnimation()
            } else {
                stopAnimations()
            }
        }
    }

    // MARK: - Recording Ring

    private var recordingRing: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .red.opacity(0.8),
                        .red.opacity(0.4),
                        .red.opacity(0.8),
                    ]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                lineWidth: 4
            )
            .frame(width: ringSize, height: ringSize)
            .rotationEffect(.degrees(ringRotation))
            .opacity(isPaused ? 0.5 : 1.0)
    }

    // MARK: - Pulsing Background

    private var pulsingBackground: some View {
        Circle()
            .fill(Color.red.opacity(0.2))
            .frame(width: buttonSize + 30, height: buttonSize + 30)
            .scaleEffect(pulseScale + CGFloat(audioLevel) * 0.3)
            .animation(.easeInOut(duration: 0.1), value: audioLevel)
    }

    // MARK: - Main Button

    private var mainButton: some View {
        Button(action: {
            HapticManager.shared.impact(.medium)
            action()
        }) {
            ZStack {
                // Button background
                Circle()
                    .fill(buttonGradient)
                    .frame(width: buttonSize, height: buttonSize)
                    .shadow(
                        color: buttonShadowColor, radius: isPressing ? 4 : 8, y: isPressing ? 2 : 4)

                // Button content
                buttonContent
            }
        }
        .buttonStyle(RecordButtonStyle())
        .scaleEffect(isPressing ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressing = true }
                .onEnded { _ in isPressing = false }
        )
        .disabled(isProcessing)
    }

    @ViewBuilder
    private var buttonContent: some View {
        if isProcessing {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
        } else if isRecording {
            // Stop icon (rounded square)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 28, height: 28)
        } else if isPaused {
            // Resume icon (play)
            Image(systemName: "play.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
                .offset(x: 3)  // Visual centering for play icon
        } else {
            // Record icon (circle)
            Circle()
                .fill(Color.white)
                .frame(width: 32, height: 32)
        }
    }

    private var buttonGradient: LinearGradient {
        if isProcessing {
            return LinearGradient(
                colors: [.gray, .gray.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if isPaused {
            return LinearGradient(
                colors: [.orange, .orange.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [.red, .red.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var buttonShadowColor: Color {
        if isProcessing {
            return .gray.opacity(0.3)
        } else if isPaused {
            return .orange.opacity(0.4)
        } else {
            return .red.opacity(0.4)
        }
    }

    // MARK: - Animations

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }

    private func startRingAnimation() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
    }

    private func stopAnimations() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.0
        }
        ringRotation = 0
    }
}

// MARK: - Button Style

struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Secondary Action Button

struct RecordingActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(color)
                }

                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Pause/Resume Button

struct PauseResumeButton: View {
    let isPaused: Bool
    let action: () -> Void

    var body: some View {
        RecordingActionButton(
            icon: isPaused ? "play.fill" : "pause.fill",
            label: isPaused ? "Resume" : "Pause",
            color: .orange,
            action: action
        )
    }
}

// MARK: - Cancel Button

struct CancelRecordingButton: View {
    let action: () -> Void

    var body: some View {
        RecordingActionButton(
            icon: "xmark",
            label: "Cancel",
            color: .red,
            action: action
        )
    }
}

// MARK: - Done Button

struct DoneRecordingButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.impact(.medium)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                Text("Done")
            }
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .tint(isEnabled ? .green : .gray)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        VStack(spacing: 40) {
            // Idle state
            RecordButton(
                isRecording: false,
                isPaused: false,
                isProcessing: false,
                audioLevel: 0,
                action: {}
            )

            // Recording state
            RecordButton(
                isRecording: true,
                isPaused: false,
                isProcessing: false,
                audioLevel: 0.5,
                action: {}
            )

            // Paused state
            RecordButton(
                isRecording: false,
                isPaused: true,
                isProcessing: false,
                audioLevel: 0,
                action: {}
            )

            HStack(spacing: 40) {
                CancelRecordingButton(action: {})
                PauseResumeButton(isPaused: false, action: {})
            }

            DoneRecordingButton(isEnabled: true, action: {})
        }
        .padding()
    }
#endif
