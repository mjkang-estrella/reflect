import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var transcriptText: String = ""
    @Published var showError = false
    @Published var errorMessage = ""

    private let provider: TranscriptionProvider
    private var hasSpeechPermission = false
    private var hasMicPermission = false

    init(provider: TranscriptionProvider? = nil) {
        self.provider = provider ?? OnDeviceSpeechTranscriptionProvider()
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
                state = .recording
            } catch {
                handleError(error)
            }
        }
    }

    func pauseRecording() {
        provider.stop()
        state = .paused
    }

    func resumeRecording() {
        startRecording()
    }

    func stopAndReset() {
        provider.cancel()
        transcriptText = ""
        state = .idle
    }

    private func requestPermissionsIfNeeded() async -> Bool {
        if hasSpeechPermission && hasMicPermission {
            return true
        }

        let speechStatus = await requestSpeechAuthorization()
        hasSpeechPermission = speechStatus == .authorized

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
        updateTranscript(with: text)
    }

    private func handleFinal(_ text: String) {
        updateTranscript(with: text)
    }

    private func updateTranscript(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcriptText = trimmed
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
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
