import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss

<<<<<<< ours
=======
<<<<<<< ours
    @State private var recordingState: RecordingState = .recording
    @State private var transcription = RecordingTranscription.sample
    @State private var followUp = FollowUpSuggestion.sample
=======
>>>>>>> theirs
    let backgroundOpacity: Double
    let onDismiss: (() -> Void)?

    @State private var recordingState: RecordingState = .recording
    @State private var transcription = RecordingTranscription.sample
    @State private var followUp = FollowUpSuggestion.sample
    @State private var showExitConfirmation = false

    init(backgroundOpacity: Double = 1.0, onDismiss: (() -> Void)? = nil) {
        self.backgroundOpacity = backgroundOpacity
        self.onDismiss = onDismiss
    }
<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    headerStatus
                        .padding(.top, 22)
                        .padding(.horizontal, 32)

                    transcriptionCard
                        .padding(.horizontal, 16)
                        .padding(.top, 34)

                    followUpCard
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    Spacer()

                    controlsSection
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
<<<<<<< ours
=======
<<<<<<< ours
=======
>>>>>>> theirs
            .alert("Discard recording?", isPresented: $showExitConfirmation) {
                Button("Keep Recording", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    recordingState = .idle
                    performDismiss()
                }
            } message: {
                Text("Your recording will be lost.")
            }
<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: 0x1E2343),
                Color(hex: 0x3B3A68),
                Color(hex: 0xE8A69E),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
<<<<<<< ours
        .opacity(backgroundOpacity)
=======
<<<<<<< ours
=======
        .opacity(backgroundOpacity)
>>>>>>> theirs
>>>>>>> theirs
        .ignoresSafeArea()
    }

    private var headerStatus: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: 0xFB2C36).opacity(0.52))
                .frame(width: 8, height: 8)

            Text(recordingState.statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.8))

            Spacer()
        }
    }

    private var transcriptionCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(transcription.lines) { line in
                    Text(line.text)
                        .font(line.isEmphasized
                            ? .system(size: 24, weight: .regular, design: .serif)
                            : .system(size: 20, weight: .regular, design: .serif)
                        )
                        .foregroundColor(Color(hex: line.textColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 414)
        .scrollIndicators(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color(hex: 0xF0F2F5))
                .shadow(color: Color.black.opacity(0.16), radius: 20, y: 12)
        )
    }

    private var followUpCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0xFAF5FF))
                    .frame(width: 28, height: 28)

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0x6E11B0))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(followUp.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x6E11B0))
                    .tracking(0.6)

                Text(followUp.prompt)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundColor(Color(hex: 0x1D293D))
            }

            Spacer()

            Button(action: regenerateFollowUp) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: 0x6B7280))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.16), radius: 20, y: 12)
        )
    }

    private var controlsSection: some View {
<<<<<<< ours
=======
<<<<<<< ours
        VStack(spacing: 20) {
            if recordingState == .finished {
                Button(action: saveRecording) {
                    Text("Save as Journal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: 0x0F1115))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.15), radius: 12, y: 6)
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 32) {
                RecordingControlButton(
                    systemName: "xmark",
                    isHighlighted: false,
                    action: cancelRecording
                )

                RecordingPrimaryButton(
                    state: recordingState,
                    action: togglePrimaryAction
                )

                RecordingControlButton(
                    systemName: recordingState == .paused ? "play.fill" : "pause.fill",
                    isHighlighted: recordingState == .paused,
                    action: togglePause
                )
=======
>>>>>>> theirs
        HStack(spacing: 32) {
            RecordingControlButton(
                systemName: "xmark",
                isHighlighted: false,
                action: cancelRecording
            )

            RecordingPrimaryButton(
                state: recordingState,
                action: togglePrimaryAction
            )

            if recordingState == .paused {
                RecordingConfirmButton(action: saveRecording)
            } else {
                Color.clear
                    .frame(width: 56, height: 56)
<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs
            }
        }
    }

    private func togglePrimaryAction() {
        switch recordingState {
        case .idle:
            recordingState = .recording
        case .recording:
<<<<<<< ours
            recordingState = .paused
        case .paused:
            recordingState = .recording
=======
<<<<<<< ours
            recordingState = .finished
        case .paused:
            recordingState = .recording
        case .finished:
            recordingState = .idle
        }
    }

    private func togglePause() {
        switch recordingState {
        case .recording:
            recordingState = .paused
        case .paused:
            recordingState = .recording
        default:
            break
=======
            recordingState = .paused
        case .paused:
            recordingState = .recording
>>>>>>> theirs
>>>>>>> theirs
        }
    }

    private func cancelRecording() {
<<<<<<< ours
=======
<<<<<<< ours
        recordingState = .idle
        dismiss()
=======
>>>>>>> theirs
        if recordingState.isActive {
            showExitConfirmation = true
            return
        }
        recordingState = .idle
        performDismiss()
<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs
    }

    private func regenerateFollowUp() {
        followUp = FollowUpSuggestion(
            label: "AI FOLLOW-UP",
            prompt: "What would the boldest version of you try next?"
        )
    }

    private func saveRecording() {
        recordingState = .idle
<<<<<<< ours
=======
<<<<<<< ours
        dismiss()
=======
>>>>>>> theirs
        performDismiss()
    }

    private func performDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs
    }
}

private enum RecordingState {
    case idle
    case recording
    case paused
<<<<<<< ours
=======
<<<<<<< ours
    case finished
=======
>>>>>>> theirs

    var isActive: Bool {
        switch self {
        case .recording, .paused:
            return true
        case .idle:
            return false
        }
    }
<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs

    var statusText: String {
        switch self {
        case .idle:
            return "Ready to record"
        case .recording:
            return "Recording voice..."
        case .paused:
            return "Recording paused"
<<<<<<< ours
=======
<<<<<<< ours
        case .finished:
            return "Recording complete"
=======
>>>>>>> theirs
>>>>>>> theirs
        }
    }
}

private struct RecordingTranscription {
    let lines: [RecordingLine]

    static let sample = RecordingTranscription(lines: [
        RecordingLine(text: "Okay...", textColor: 0x90A1B9),
        RecordingLine(
            text: "I've been thinking about this design a lot today.",
            textColor: 0x62748E
        ),
        RecordingLine(
            text: "I keep coming back to the feeling that it's... too clean. Like it looks right, but it doesn't feel right yet.",
            textColor: 0x62748E
        ),
        RecordingLine(
            text: "Um... maybe it's because everything is solved too early. There's no tension.",
            textColor: 0x62748E
        ),
        RecordingLine(
            text: "I think good design needs a bit of resistance. Not friction in usability, but... emotional friction.",
            textColor: 0x45556C
        ),
        RecordingLine(
            text: "Like, something that makes you pause for half a second.",
            textColor: 0x0F172B,
            isEmphasized: true
        ),
    ])
}

private struct RecordingLine: Identifiable {
    let id = UUID()
    let text: String
    let textColor: Int
    var isEmphasized: Bool = false
}

private struct FollowUpSuggestion {
    let label: String
    let prompt: String

    static let sample = FollowUpSuggestion(
        label: "AI FOLLOW-UP",
        prompt: "What would the best version of yourself do?"
    )
}

private struct RecordingControlButton: View {
    let systemName: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isHighlighted ? Color(hex: 0x0F1115) : Color(hex: 0x111827))
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct RecordingPrimaryButton: View {
    let state: RecordingState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x0F1115))
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.25), radius: 20, y: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .opacity(state == .recording ? 1 : 0)

                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
<<<<<<< ours
                    .opacity(state == .idle || state == .paused ? 1 : 0)
=======
<<<<<<< ours
                    .opacity(state == .idle ? 1 : 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: 2)
                    .opacity(state == .paused ? 1 : 0)
=======
                    .opacity(state == .idle || state == .paused ? 1 : 0)
>>>>>>> theirs
>>>>>>> theirs
            }
        }
        .buttonStyle(.plain)
    }
}

<<<<<<< ours
=======
<<<<<<< ours
=======
>>>>>>> theirs
private struct RecordingConfirmButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color(hex: 0x22C55E))
                        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
                )
        }
        .buttonStyle(.plain)
    }
}

<<<<<<< ours
=======
>>>>>>> theirs
>>>>>>> theirs
private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        RecordingView()
    }
#endif
