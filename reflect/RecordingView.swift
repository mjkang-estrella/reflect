import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore

    let backgroundOpacity: Double
    let onDismiss: (() -> Void)?

    private let transcriptBottomID = "transcript-bottom"

    @StateObject private var viewModel = RecordingViewModel()
    @State private var transcription = RecordingTranscription.sample
    @State private var followUp = FollowUpSuggestion.sample
    @State private var showExitConfirmation = false

    init(backgroundOpacity: Double = 1.0, onDismiss: (() -> Void)? = nil) {
        self.backgroundOpacity = backgroundOpacity
        self.onDismiss = onDismiss
    }

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
            .alert("Discard recording?", isPresented: $showExitConfirmation) {
                Button("Keep Recording", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    viewModel.stopAndReset()
                    performDismiss()
                }
            } message: {
                Text("Your recording will be lost.")
            }
            .alert("Recording Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .onDisappear {
                viewModel.stopAndReset()
            }
        }
    }

    private var backgroundGradient: some View {
        AppGradientBackground(opacity: backgroundOpacity)
    }

    private var headerStatus: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: 0xFB2C36).opacity(0.52))
                .frame(width: 8, height: 8)

            Text(viewModel.state.statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.8))

            Spacer()
        }
    }

    private var transcriptionCard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(transcriptionLines) { line in
                        Text(line.text)
                            .font(line.isEmphasized
                                ? .system(size: 24, weight: .regular, design: .serif)
                                : .system(size: 20, weight: .regular, design: .serif)
                            )
                            .foregroundColor(Color(hex: line.textColor))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(transcriptBottomID)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollTranscriptToBottom(proxy, animated: false)
            }
            .onChange(of: viewModel.transcriptText) { _ in
                scrollTranscriptToBottom(proxy, animated: viewModel.currentLine.isEmpty)
            }
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
        HStack(spacing: 32) {
            RecordingControlButton(
                systemName: "xmark",
                isHighlighted: false,
                action: cancelRecording
            )

            RecordingPrimaryButton(
                state: viewModel.state,
                action: togglePrimaryAction
            )

            if viewModel.state == .paused {
                if viewModel.isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: 56, height: 56)
                } else {
                    RecordingConfirmButton(action: saveRecording)
                }
            } else {
                Color.clear
                    .frame(width: 56, height: 56)
            }
        }
    }

    private func togglePrimaryAction() {
        switch viewModel.state {
        case .idle:
            viewModel.startRecording()
        case .recording:
            viewModel.pauseRecording()
        case .paused:
            viewModel.resumeRecording()
        }
    }

    private func cancelRecording() {
        if viewModel.state.isActive {
            showExitConfirmation = true
            return
        }
        viewModel.stopAndReset()
        performDismiss()
    }

    private func regenerateFollowUp() {
        followUp = FollowUpSuggestion(
            label: "AI FOLLOW-UP",
            prompt: "What would the boldest version of you try next?"
        )
    }

    private func saveRecording() {
        guard !viewModel.isSaving else { return }
        guard let userId = authStore.userId, let userUUID = UUID(uuidString: userId) else {
            viewModel.presentError("Sign in to save this recording.")
            return
        }

        Task {
            let saved = await viewModel.saveRecording(
                userId: userUUID,
                followUpPrompt: followUp.prompt
            )
            if saved {
                viewModel.stopAndReset()
                performDismiss()
            }
        }
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(transcriptBottomID, anchor: .bottom)
            }
        }
    }

    private func performDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var transcriptionLines: [RecordingLine] {
        let committed = viewModel.committedLines
        let current = viewModel.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if viewModel.state == .idle && committed.isEmpty && current.isEmpty {
            return transcription.lines
        }

        var lines = committed.enumerated().map { index, text in
            RecordingLine(id: "committed-\(index)", text: text, textColor: 0x45556C)
        }

        if !current.isEmpty {
            lines.append(
                RecordingLine(
                    id: "current",
                    text: current,
                    textColor: 0x0F172B,
                    isEmphasized: true
                )
            )
            return lines
        }

        if lines.isEmpty {
            return [RecordingLine(id: "placeholder", text: "Listening...", textColor: 0x90A1B9)]
        }

        return lines
    }
}

private struct RecordingTranscription {
    let lines: [RecordingLine]

    static let sample = RecordingTranscription(lines: [
        RecordingLine(text: "Speak about your day.", textColor: 0x90A1B9),
        RecordingLine(text: "Start with whatever feels real.", textColor: 0x62748E),
        RecordingLine(
            text: "I'm listening.",
            textColor: 0x0F172B,
            isEmphasized: true
        ),
    ])
}

private struct RecordingLine: Identifiable {
    let id: String
    let text: String
    let textColor: Int
    var isEmphasized: Bool = false

    init(id: String = UUID().uuidString, text: String, textColor: Int, isEmphasized: Bool = false) {
        self.id = id
        self.text = text
        self.textColor = textColor
        self.isEmphasized = isEmphasized
    }
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
                    .opacity(state == .idle || state == .paused ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }
}

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

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        RecordingView()
    }
#endif
