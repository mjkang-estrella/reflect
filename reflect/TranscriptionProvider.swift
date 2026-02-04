import AVFoundation
import Foundation
import Speech

protocol TranscriptionProvider: AnyObject {
    var requiresSpeechAuthorization: Bool { get }
    var onPartial: ((String) -> Void)? { get set }
    var onFinal: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func start() throws
    func stop()
    func cancel()
}

enum TranscriptionProviderError: LocalizedError {
    case recognizerUnavailable
    case audioEngineUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available right now."
        case .audioEngineUnavailable:
            return "Audio engine is unavailable."
        }
    }
}

final class OnDeviceSpeechTranscriptionProvider: NSObject, TranscriptionProvider {
    let requiresSpeechAuthorization = true
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRecording = false
    private var isTapInstalled = false
    private var restartWorkItem: DispatchWorkItem?
    private var committedSegments: [SpeechSegment] = []
    private var currentSegments: [SpeechSegment] = []
    private var lastCommittedEndTime: TimeInterval = 0
    private var lastSeenEndTime: TimeInterval = 0
    private var segmentOffset: TimeInterval = 0

    private let segmentMatchTolerance: TimeInterval = 0.04
    private let taskRestartGap: TimeInterval = 1.3

    private struct SpeechSegment {
        var timestamp: TimeInterval
        var duration: TimeInterval
        var text: String

        var endTime: TimeInterval {
            timestamp + duration
        }
    }

    func start() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionProviderError.recognizerUnavailable
        }

        isRecording = true
        restartWorkItem?.cancel()
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        if inputNode.numberOfInputs == 0 {
            throw TranscriptionProviderError.audioEngineUnavailable
        }

        if !isTapInstalled {
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            isTapInstalled = true
        }

        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }

        startRecognitionTask(using: recognizer)
    }

    private func startRecognitionTask(using recognizer: SFSpeechRecognizer) {
        recognitionTask?.cancel()
        recognitionTask = nil

        let anchorTime = max(lastCommittedEndTime, lastSeenEndTime)
        if anchorTime > 0 {
            segmentOffset = anchorTime + taskRestartGap
        } else {
            segmentOffset = 0
        }
        currentSegments = []

        recognitionRequest?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error {
                self?.onError?(error)
                if let self, self.isRecording {
                    self.scheduleRecognitionRestart()
                }
                return
            }

            guard let result else { return }
            self?.handleRecognitionResult(result)
        }
    }

    func stop() {
        isRecording = false
        restartWorkItem?.cancel()
        finalizeCurrentSegments()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        recognitionRequest?.endAudio()
    }

    func cancel() {
        stop()
        committedSegments = []
        currentSegments = []
        lastCommittedEndTime = 0
        lastSeenEndTime = 0
        segmentOffset = 0
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func scheduleRecognitionRestart() {
        restartWorkItem?.cancel()
        finalizeCurrentSegments()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording, let recognizer = self.speechRecognizer, recognizer.isAvailable else {
                return
            }
            self.startRecognitionTask(using: recognizer)
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let incoming = segments(from: result)
        mergeCurrentSegments(with: incoming)
        flushStableSegmentsIfNeeded()
        let committedText = transcriptString(from: committedSegments, finalizeLastLine: true)
        let currentLine = currentPartialLine(from: currentSegments)
        let output = combinedTranscript(committedText: committedText, currentLine: currentLine)

        if result.isFinal {
            finalizeCurrentSegments()
            onFinal?(output)
            if isRecording, let recognizer = speechRecognizer, recognizer.isAvailable {
                startRecognitionTask(using: recognizer)
            }
        } else {
            onPartial?(output)
        }
    }

    private func segments(from result: SFSpeechRecognitionResult) -> [SpeechSegment] {
        result.bestTranscription.segments.compactMap { segment in
            let token = segment.substring.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            return SpeechSegment(
                timestamp: segment.timestamp,
                duration: segment.duration,
                text: token
            )
        }
    }

    private func mergeCurrentSegments(with incoming: [SpeechSegment]) {
        guard !incoming.isEmpty else { return }
        for segment in incoming {
            if let index = currentSegments.firstIndex(where: { abs($0.timestamp - segment.timestamp) < segmentMatchTolerance }) {
                currentSegments[index].text = segment.text
                currentSegments[index].duration = segment.duration
            } else if let insertIndex = currentSegments.firstIndex(where: { $0.timestamp > segment.timestamp }) {
                currentSegments.insert(segment, at: insertIndex)
            } else {
                currentSegments.append(segment)
            }
        }

        if let maxEnd = currentSegments.map(\.endTime).max() {
            lastSeenEndTime = max(lastSeenEndTime, segmentOffset + maxEnd)
        }
    }

    private func flushStableSegmentsIfNeeded() {
        guard !currentSegments.isEmpty else { return }

        var lastBoundaryIndex: Int?
        var lastEndTime: TimeInterval?

        for (index, segment) in currentSegments.enumerated() {
            let gap = lastEndTime.map { max(0, segment.timestamp - $0) } ?? 0
            if gap > 1.2, index > 0 {
                lastBoundaryIndex = index - 1
            }

            let token = segment.text
            if token.hasSuffix(".") || token.hasSuffix("?") || token.hasSuffix("!") {
                lastBoundaryIndex = index
            }

            lastEndTime = segment.endTime
        }

        guard let boundaryIndex = lastBoundaryIndex, boundaryIndex >= 0 else { return }
        let stableSegments = Array(currentSegments.prefix(boundaryIndex + 1))
        let finalized = offsetSegments(stableSegments, by: segmentOffset)
        committedSegments.append(contentsOf: finalized)
        currentSegments.removeFirst(boundaryIndex + 1)

        if let maxEnd = finalized.map(\.endTime).max() {
            lastCommittedEndTime = max(lastCommittedEndTime, maxEnd)
            lastSeenEndTime = max(lastSeenEndTime, lastCommittedEndTime)
        }
    }

    private func offsetSegments(_ segments: [SpeechSegment], by offset: TimeInterval) -> [SpeechSegment] {
        segments.map { segment in
            SpeechSegment(timestamp: segment.timestamp + offset, duration: segment.duration, text: segment.text)
        }
    }

    private func finalizeCurrentSegments() {
        guard !currentSegments.isEmpty else { return }
        let finalized = offsetSegments(currentSegments, by: segmentOffset)
        committedSegments.append(contentsOf: finalized)
        if let maxEnd = finalized.map(\.endTime).max() {
            lastCommittedEndTime = max(lastCommittedEndTime, maxEnd)
            lastSeenEndTime = max(lastSeenEndTime, lastCommittedEndTime)
        }
        currentSegments = []
    }

    private func transcriptString(from segments: [SpeechSegment], finalizeLastLine: Bool) -> String {
        guard !segments.isEmpty else { return "" }

        var lines: [String] = []
        var currentLine = ""
        var lastEndTime: TimeInterval?

        for segment in segments {
            let gap = lastEndTime.map { max(0, segment.timestamp - $0) } ?? 0
            if gap > 1.2 {
                flushLine(&currentLine, into: &lines, appendPeriodIfMissing: true)
            }

            let token = segment.text
            if currentLine.isEmpty {
                currentLine = token
            } else {
                currentLine.append(" \(token)")
            }

            if token.hasSuffix(".") || token.hasSuffix("?") || token.hasSuffix("!") {
                flushLine(&currentLine, into: &lines, appendPeriodIfMissing: false)
            }

            lastEndTime = segment.endTime
        }

        if finalizeLastLine {
            flushLine(&currentLine, into: &lines, appendPeriodIfMissing: true)
        } else {
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func currentPartialLine(from segments: [SpeechSegment]) -> String {
        guard !segments.isEmpty else { return "" }

        var currentLine = ""
        var lastEndTime: TimeInterval?

        for segment in segments {
            let gap = lastEndTime.map { max(0, segment.timestamp - $0) } ?? 0
            if gap > 1.2 {
                currentLine = ""
            }

            let token = segment.text
            if currentLine.isEmpty {
                currentLine = token
            } else {
                currentLine.append(" \(token)")
            }

            if token.hasSuffix(".") || token.hasSuffix("?") || token.hasSuffix("!") {
                currentLine = ""
            }

            lastEndTime = segment.endTime
        }

        return currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func combinedTranscript(committedText: String, currentLine: String) -> String {
        guard !currentLine.isEmpty else { return committedText }
        guard !committedText.isEmpty else { return currentLine }
        return "\(committedText)\n\(currentLine)"
    }

    private func flushLine(
        _ currentLine: inout String,
        into lines: inout [String],
        appendPeriodIfMissing: Bool
    ) {
        let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let line = appendPeriodIfMissing ? ensureTerminalPunctuation(for: trimmed) : trimmed
        lines.append(line)
        currentLine = ""
    }

    private func ensureTerminalPunctuation(for line: String) -> String {
        guard let last = line.last else { return line }
        if last == "." || last == "?" || last == "!" {
            return line
        }
        return "\(line)."
    }
}
