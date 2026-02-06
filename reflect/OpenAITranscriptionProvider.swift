import AVFoundation
import Foundation
import Supabase

final class OpenAITranscriptionProvider: NSObject, TranscriptionProvider {
    let requiresSpeechAuthorization = false
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var recordingFileURL: URL? { recordingURL }

    private let supabase: SupabaseClient?
    private let functionName: String
    private let transcriptionInterval: TimeInterval = 2.2
    private let minimumAudioBytes = 2_000
    private let maxTranscriptionAudioBytes = 8 * 1024 * 1024
    private let promptLimit = 2_000
    private let recordingMimeType = "audio/wav"
    private let recordingFileName = "recording.wav"

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var transcriptionTimer: DispatchSourceTimer?
    private var isTranscribing = false
    private var hasEmittedSizeLimitError = false
    private var lastTranscript: String = ""
    private var committedTranscript: String = ""
    private var currentSegmentTranscript: String = ""
    private var shouldStartNewSegment = false
    private var sessionStartedAt: Date?
    private var hasTrackedFirstPartial = false

    init(
        client: SupabaseClient? = try? SupabaseClientProvider.makeClient(),
        functionNameOverride: String? = nil,
        initialTranscript: String = ""
    ) {
        self.supabase = client
        self.functionName = functionNameOverride ?? TranscriptionRuntimeSettings.selectedBackend().functionName
        let seeded = initialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastTranscript = seeded
        self.committedTranscript = seeded
        super.init()
    }

    func start() throws {
        guard let supabase else {
            onError?(OpenAITranscriptionError.missingSupabaseConfig)
            return
        }

        if audioRecorder == nil || shouldStartNewSegment {
            try configureAudioSession()
            let session = AVAudioSession.sharedInstance()
            if !session.isInputAvailable {
                let message = """
                Audio input unavailable. \
                route=\(routeSummary(from: session.currentRoute)). \
                On Simulator: I/O > Audio Input > Mac Microphone.
                """
                onError?(OpenAITranscriptionErrorDetail(message: message))
                return
            }
            let url = makeRecordingURL()
            recordingURL = url
            audioRecorder = try createRecorder(at: url)
            currentSegmentTranscript = ""
            shouldStartNewSegment = false
            hasEmittedSizeLimitError = false
        }

        if let recorder = audioRecorder, !recorder.isRecording {
            if !recorder.record() {
                let session = AVAudioSession.sharedInstance()
                let permission = session.recordPermission
                let permissionText: String
                switch permission {
                case .undetermined:
                    permissionText = "undetermined"
                case .denied:
                    permissionText = "denied"
                case .granted:
                    permissionText = "granted"
                @unknown default:
                    permissionText = "unknown"
                }
                let message = """
                Failed to start audio recording. \
                permission=\(permissionText), \
                category=\(session.category.rawValue), \
                mode=\(session.mode.rawValue), \
                sampleRate=\(session.sampleRate), \
                route=\(routeSummary(from: session.currentRoute))
                """
                onError?(OpenAITranscriptionErrorDetail(message: message))
                return
            }
        }

        sessionStartedAt = Date()
        hasTrackedFirstPartial = false
        TranscriptionTelemetry.track("transcription_session_started", fields: [
            "transport": "polling",
            "function": functionName,
        ])
        startTranscriptionTimer(using: supabase)
    }

    func stop() {
        audioRecorder?.stop()
        audioRecorder = nil
        stopTranscriptionTimer()
        shouldStartNewSegment = true
        Task { await transcribeFinal(finalizeSegment: true) }
    }

    func cancel() {
        audioRecorder?.stop()
        audioRecorder = nil
        stopTranscriptionTimer()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        isTranscribing = false
        hasEmittedSizeLimitError = false
        lastTranscript = ""
        committedTranscript = ""
        currentSegmentTranscript = ""
        shouldStartNewSegment = false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .allowBluetooth, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func createRecorder(at url: URL) throws -> AVAudioRecorder {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        if !recorder.prepareToRecord() {
            throw OpenAITranscriptionErrorDetail(message: "Failed to prepare audio recorder.")
        }
        return recorder
    }

    private func makeRecordingURL() -> URL {
        let filename = "recording-\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func startTranscriptionTimer(using supabase: SupabaseClient) {
        transcriptionTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + transcriptionInterval, repeating: transcriptionInterval)
        timer.setEventHandler { [weak self] in
            self?.transcribePartial(using: supabase)
        }
        transcriptionTimer = timer
        timer.resume()
    }

    private func stopTranscriptionTimer() {
        transcriptionTimer?.cancel()
        transcriptionTimer = nil
    }

    private func transcribePartial(using supabase: SupabaseClient) {
        guard !isTranscribing else { return }
        guard let url = recordingURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard data.count >= minimumAudioBytes else { return }
        guard data.count <= maxTranscriptionAudioBytes else {
            emitSizeLimitErrorIfNeeded()
            return
        }

        hasEmittedSizeLimitError = false
        isTranscribing = true

        let request = TranscribeRequest(
            audioBase64: data.base64EncodedString(),
            mimeType: recordingMimeType,
            fileName: recordingFileName,
            prompt: promptSuffix(from: lastTranscript)
        )

        Task {
            defer { self.isTranscribing = false }
            do {
                let response: TranscribeResponse = try await supabase.functions.invoke(
                    functionName,
                    options: FunctionInvokeOptions(body: request)
                )
                let normalized = normalizeTranscript(response.text)
                guard !normalized.isEmpty else { return }
                self.trackFirstPartialIfNeeded()
                self.currentSegmentTranscript = normalized
                let combined = self.combineTranscript(committed: self.committedTranscript, current: normalized)
                if combined != self.lastTranscript {
                    self.lastTranscript = combined
                    self.onPartial?(combined)
                }
            } catch {
                if self.shouldIgnorePartialTranscriptionError(error) {
                    return
                }
                self.onError?(self.detailedError(from: error))
            }
        }
    }

    private func transcribeFinal(finalizeSegment: Bool) async {
        guard let supabase else { return }
        guard let url = recordingURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard data.count >= minimumAudioBytes else { return }
        guard data.count <= maxTranscriptionAudioBytes else {
            onError?(
                OpenAITranscriptionErrorDetail(
                    message: "Final transcription payload too large (\(data.count) bytes). Pause and resume to start a new segment."
                )
            )
            return
        }
        guard !isTranscribing else { return }
        isTranscribing = true
        defer { isTranscribing = false }

        let request = TranscribeRequest(
            audioBase64: data.base64EncodedString(),
            mimeType: recordingMimeType,
            fileName: recordingFileName,
            prompt: promptSuffix(from: lastTranscript)
        )

        do {
            let response: TranscribeResponse = try await supabase.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(body: request)
            )
            let normalized = normalizeTranscript(response.text)
            guard !normalized.isEmpty else { return }
            trackFirstPartialIfNeeded()
            currentSegmentTranscript = normalized
            let combined = combineTranscript(committed: committedTranscript, current: normalized)
            lastTranscript = combined
            onFinal?(combined)
            if finalizeSegment {
                committedTranscript = combined
                currentSegmentTranscript = ""
            }
        } catch {
            onError?(detailedError(from: error))
        }
    }

    private func emitSizeLimitErrorIfNeeded() {
        guard !hasEmittedSizeLimitError else { return }
        hasEmittedSizeLimitError = true
        onError?(
            OpenAITranscriptionErrorDetail(
                message: "Transcription segment reached size limit. Pause and resume recording to start a new segment."
            )
        )
    }

    private func promptSuffix(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= promptLimit { return trimmed }
        return String(trimmed.suffix(promptLimit))
    }

    private func combineTranscript(committed: String, current: String) -> String {
        let trimmedCommitted = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommitted.isEmpty { return trimmedCurrent }
        if trimmedCurrent.isEmpty { return trimmedCommitted }
        return "\(trimmedCommitted)\n\(trimmedCurrent)"
    }

    private func normalizeTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
        guard let regex = try? NSRegularExpression(pattern: "([.!?])\\s+") else {
            return normalized
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "$1\n")
    }

    private func routeSummary(from route: AVAudioSessionRouteDescription) -> String {
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
        return "in[\(inputs.joined(separator: ","))] out[\(outputs.joined(separator: ","))]"
    }

    private func detailedError(from error: Error) -> Error {
        if let functionsError = error as? FunctionsError {
            switch functionsError {
            case .httpError(let code, let responseData):
                let responseText = String(data: responseData, encoding: .utf8) ?? ""
                return OpenAITranscriptionErrorDetail(
                    message: "Transcription failed (HTTP \(code)). \(responseText)"
                )
            case .relayError:
                return OpenAITranscriptionErrorDetail(
                    message: "Transcription relay error. Check your Supabase function deployment."
                )
            }
        }

        return OpenAITranscriptionErrorDetail(message: error.localizedDescription)
    }

    private func shouldIgnorePartialTranscriptionError(_ error: Error) -> Bool {
        guard let functionsError = error as? FunctionsError else { return false }
        guard case let .httpError(code, responseData) = functionsError, code == 400 else { return false }
        let responseText = String(data: responseData, encoding: .utf8)?.lowercased() ?? ""
        return responseText.contains("audio file might be corrupted or unsupported") || responseText.contains("\"code\":\"invalid_value\"")
    }

    private func trackFirstPartialIfNeeded() {
        guard !hasTrackedFirstPartial else { return }
        hasTrackedFirstPartial = true
        let elapsedMs = Int((Date().timeIntervalSince(sessionStartedAt ?? Date())) * 1000)
        TranscriptionTelemetry.track("transcription_first_partial_ms", fields: [
            "transport": "polling",
            "value": "\(max(elapsedMs, 0))",
        ])
    }
}

private struct TranscribeRequest: Encodable {
    let audioBase64: String
    let mimeType: String
    let fileName: String
    let prompt: String?
}

private struct TranscribeResponse: Decodable {
    let text: String
}

private enum OpenAITranscriptionError: LocalizedError {
    case missingSupabaseConfig

    var errorDescription: String? {
        "Supabase configuration is missing. Check SUPABASE_URL and SUPABASE_ANON_KEY."
    }
}

private struct OpenAITranscriptionErrorDetail: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
