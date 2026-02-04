import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var transcriptText: String = ""
    @Published private(set) var committedLines: [String] = []
    @Published private(set) var currentLine: String = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private(set) var isSaving = false

    private let provider: TranscriptionProvider
    private var hasSpeechPermission = false
    private var hasMicPermission = false
    private var sessionStartedAt: Date?
    private var activeRecordingStart: Date?
    private var accumulatedDuration: TimeInterval = 0

    init(provider: TranscriptionProvider? = nil) {
        self.provider = provider ?? OpenAITranscriptionProvider()
        self.provider.onPartial = { [weak self] text in
            Task { @MainActor in
                self?.handlePartial(text)
            }
        }
        self.provider.onFinal = { [weak self] text in
            Task { @MainActor in
                self?.handleFinal(text)
            }
        }
        self.provider.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleError(error)
            }
        }
    }

    func startRecording() {
        Task {
            let authorized = await requestPermissionsIfNeeded()
            guard authorized else { return }

            do {
                try provider.start()
                if sessionStartedAt == nil {
                    sessionStartedAt = Date()
                }
                activeRecordingStart = Date()
                state = .recording
            } catch {
                handleError(error)
            }
        }
    }

    func pauseRecording() {
        provider.stop()
        accumulateDuration()
        state = .paused
    }

    func resumeRecording() {
        startRecording()
    }

    func stopAndReset() {
        provider.cancel()
        transcriptText = ""
        committedLines = []
        currentLine = ""
        state = .idle
        sessionStartedAt = nil
        activeRecordingStart = nil
        accumulatedDuration = 0
    }

    private func requestPermissionsIfNeeded() async -> Bool {
        if (!provider.requiresSpeechAuthorization || hasSpeechPermission) && hasMicPermission {
            return true
        }

        if provider.requiresSpeechAuthorization {
            let speechStatus = await requestSpeechAuthorization()
            hasSpeechPermission = speechStatus == .authorized
        } else {
            hasSpeechPermission = true
        }

        let micAllowed = await requestMicrophoneAuthorization()
        hasMicPermission = micAllowed

        guard hasSpeechPermission && hasMicPermission else {
            handleError(RecordingPermissionError.denied)
            return false
        }

        return true
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func handlePartial(_ text: String) {
        updateTranscript(with: text, finalizeCurrentLine: false)
    }

    private func handleFinal(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            updateTranscript(with: text, finalizeCurrentLine: true)
        }
    }

    private func updateTranscript(with text: String, finalizeCurrentLine: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcriptText = trimmed

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if finalizeCurrentLine {
            committedLines = lines
            currentLine = ""
            return
        }

        if lines.count <= 1 {
            committedLines = []
            currentLine = lines.first ?? ""
        } else {
            committedLines = Array(lines.dropLast())
            currentLine = lines.last ?? ""
        }
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func saveRecording(userId: UUID, followUpPrompt: String?) async -> Bool {
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentError("Record something before saving.")
            return false
        }

        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let endedAt = Date()
        accumulateDuration()
        let durationSeconds = Int(accumulatedDuration.rounded())
        let startedAt = sessionStartedAt ?? endedAt

        do {
            let repository = try JournalRepository()
            try await repository.createVoiceSession(
                userId: userId,
                transcript: trimmed,
                durationSeconds: durationSeconds == 0 ? nil : durationSeconds,
                followUpPrompt: followUpPrompt,
                startedAt: startedAt,
                endedAt: endedAt
            )
            NotificationCenter.default.post(name: .journalEntriesDidChange, object: nil)
            return true
        } catch {
            presentError(error.localizedDescription)
            return false
        }
    }

    private func accumulateDuration() {
        if let activeRecordingStart {
            accumulatedDuration += Date().timeIntervalSince(activeRecordingStart)
        }
        activeRecordingStart = nil
    }
}

enum RecordingState {
    case idle
    case recording
    case paused

    var isActive: Bool {
        switch self {
        case .recording, .paused:
            return true
        case .idle:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Ready to record"
        case .recording:
            return "Recording voice..."
        case .paused:
            return "Recording paused"
        }
    }
}

enum RecordingPermissionError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Microphone and speech recognition permissions are required to record."
    }
}
