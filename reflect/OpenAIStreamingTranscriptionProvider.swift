import AVFoundation
import Foundation
import Supabase
import UIKit

final class OpenAIStreamingTranscriptionProvider: NSObject, TranscriptionProvider {
    let requiresSpeechAuthorization = false
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var recordingFileURL: URL? {
        if let fallbackURL = fallbackProvider?.recordingFileURL {
            return fallbackURL
        }
        return recordingURL
    }

    private let supabase: SupabaseClient?
    private let sessionFunctionName = "transcribe-stream-session"
    private let fallbackFunctionName = TranscriptionBackend.openAI.functionName
    private let websocketURL = URL(string: "wss://api.openai.com/v1/realtime")!
    private let recordingWriteQueue = DispatchQueue(label: "com.mjkang.reflect.transcription.streaming.recording-write")
    private let socketSendQueue = DispatchQueue(label: "com.mjkang.reflect.transcription.streaming.socket-send")

    private let sampleRate: Double = 24_000
    private let channelCount: AVAudioChannelCount = 1
    private let streamModel = "gpt-4o-transcribe"

    private var audioEngine = AVAudioEngine()
    private var isTapInstalled = false
    private var recordingURL: URL?
    private var recordingPCMURL: URL?
    private var recordingPCMHandle: FileHandle?

    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketSession: URLSession?

    private var committedItemOrder: [String] = []
    private var committedTranscripts: [String: String] = [:]
    private var partialTranscripts: [String: String] = [:]
    private var activePartialItemId: String?

    private var lastTranscript = ""
    private var committedTranscript = ""
    private var isRecordingRequested = false
    private var isStreamingActive = false
    private var hasFallenBack = false

    private var sessionStartedAt: Date?
    private var hasTrackedFirstPartial = false

    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var shouldReconnectAfterForeground = false

    private var fallbackProvider: OpenAITranscriptionProvider?

    init(client: SupabaseClient? = try? SupabaseClientProvider.makeClient()) {
        self.supabase = client
        super.init()
        registerLifecycleObservers()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func start() throws {
        if let fallbackProvider {
            try fallbackProvider.start()
            return
        }

        guard supabase != nil else {
            onError?(OpenAIStreamingTranscriptionError.missingSupabaseConfig)
            return
        }

        guard !isRecordingRequested else { return }
        isRecordingRequested = true
        hasFallenBack = false
        shouldReconnectAfterForeground = false
        sessionStartedAt = Date()
        hasTrackedFirstPartial = false
        TranscriptionTelemetry.track("transcription_session_started", fields: [
            "transport": "streaming",
            "backend": TranscriptionBackend.openAI.rawValue,
        ])

        Task {
            await startStreamingSession()
        }
    }

    func stop() {
        isRecordingRequested = false

        if let fallbackProvider {
            fallbackProvider.stop()
            return
        }

        sendEvent(type: "input_audio_buffer.commit")
        flushSocketSendQueue()
        shutdownStreamingConnection()
        stopAudioCapture()
        finishRecordingFileWrites()

        let combined = bestKnownTranscript()
        if !combined.isEmpty {
            lastTranscript = combined
            onFinal?(combined)
        }
    }

    func cancel() {
        isRecordingRequested = false
        shouldReconnectAfterForeground = false

        fallbackProvider?.cancel()
        fallbackProvider = nil

        shutdownStreamingConnection()
        stopAudioCapture()
        finishRecordingFileWrites()

        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        if let recordingPCMURL {
            try? FileManager.default.removeItem(at: recordingPCMURL)
        }
        recordingURL = nil
        recordingPCMURL = nil
        recordingPCMHandle = nil

        committedItemOrder = []
        committedTranscripts = [:]
        partialTranscripts = [:]
        activePartialItemId = nil
        committedTranscript = ""
        lastTranscript = ""
        isStreamingActive = false
    }

    private func startStreamingSession() async {
        do {
            let clientSecret = try await fetchClientSecret()
            guard isRecordingRequested else { return }

            try configureAudioSession()
            try prepareRecordingFileIfNeeded()
            connectWebSocket(clientSecret: clientSecret)
            sendSessionUpdateEvent()
            startReceiveLoop()
            try startAudioCapture()
            isStreamingActive = true
            TranscriptionTelemetry.track("transcription_transport", fields: [
                "value": "streaming",
            ])
        } catch {
            triggerFallback(reason: "stream_setup_failed", underlyingError: error)
        }
    }

    private func fetchClientSecret() async throws -> String {
        guard let supabase else {
            throw OpenAIStreamingTranscriptionError.missingSupabaseConfig
        }

        let request = StreamSessionRequest(model: streamModel)
        let options = FunctionInvokeOptions(body: request)
        let response: StreamSessionResponse = try await supabase.functions.invoke(
            sessionFunctionName,
            options: options
        )

        if let value = response.value, !value.isEmpty {
            return value
        }

        if let value = response.clientSecret?.value, !value.isEmpty {
            return value
        }

        throw OpenAIStreamingTranscriptionError.invalidSessionResponse
    }

    private func connectWebSocket(clientSecret: String) {
        let session = URLSession(configuration: .default)
        webSocketSession = session

        var request = URLRequest(url: websocketURL)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
    }

    private func sendSessionUpdateEvent() {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(sampleRate),
                        ],
                        "transcription": [
                            "model": streamModel,
                        ],
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 500,
                        ],
                    ],
                ],
            ],
        ]

        sendEvent(payload)
    }

    private func startReceiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleIncomingMessage(message)
                if self.isRecordingRequested, self.fallbackProvider == nil {
                    self.startReceiveLoop()
                }
            case .failure(let error):
                if self.isRecordingRequested, self.fallbackProvider == nil {
                    self.triggerFallback(reason: "socket_receive_failed", underlyingError: error)
                }
            }
        }
    }

    private func handleIncomingMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            return
        }

        switch type {
        case "input_audio_buffer.committed":
            if let itemId = json["item_id"] as? String, !itemId.isEmpty,
               !committedItemOrder.contains(itemId)
            {
                committedItemOrder.append(itemId)
            }
        case "conversation.item.input_audio_transcription.delta":
            handleTranscriptionDelta(json)
        case "conversation.item.input_audio_transcription.completed":
            handleTranscriptionCompleted(json)
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown streaming error"
            triggerFallback(
                reason: "provider_error_event",
                underlyingError: OpenAIStreamingTranscriptionError.provider(message)
            )
        default:
            break
        }
    }

    private func handleTranscriptionDelta(_ json: [String: Any]) {
        guard let delta = json["delta"] as? String, !delta.isEmpty else { return }

        let itemId = (json["item_id"] as? String) ?? activePartialItemId ?? UUID().uuidString
        let existing = partialTranscripts[itemId] ?? ""
        partialTranscripts[itemId] = existing + delta
        activePartialItemId = itemId

        trackFirstPartialIfNeeded(transport: "streaming")
        emitPartialUpdate()
    }

    private func handleTranscriptionCompleted(_ json: [String: Any]) {
        let itemId = (json["item_id"] as? String) ?? activePartialItemId ?? UUID().uuidString
        let rawTranscript = (json["transcript"] as? String) ?? partialTranscripts[itemId] ?? ""
        let transcript = normalizeTranscript(rawTranscript)
        guard !transcript.isEmpty else { return }

        if !committedItemOrder.contains(itemId) {
            committedItemOrder.append(itemId)
        }
        committedTranscripts[itemId] = transcript
        partialTranscripts[itemId] = nil
        if activePartialItemId == itemId {
            activePartialItemId = nil
        }

        committedTranscript = committedItemOrder
            .compactMap { committedTranscripts[$0] }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let combined = combineTranscript(committed: committedTranscript, current: "")
        lastTranscript = combined
        trackFirstPartialIfNeeded(transport: "streaming")
        onFinal?(combined)
    }

    private func emitPartialUpdate() {
        let partialId = activePartialItemId ?? Array(partialTranscripts.keys).last
        let partialText = partialId.flatMap { partialTranscripts[$0] } ?? ""
        let normalizedCurrent = normalizeTranscript(partialText)
        let combined = combineTranscript(committed: committedTranscript, current: normalizedCurrent)

        guard !combined.isEmpty, combined != lastTranscript else { return }
        lastTranscript = combined
        onPartial?(combined)
    }

    private func sendAudioChunk(_ data: Data) {
        guard !data.isEmpty else { return }
        socketSendQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRecordingRequested, self.fallbackProvider == nil else { return }
            self.sendEventOnQueue(type: "input_audio_buffer.append", additionalFields: [
                "audio": data.base64EncodedString(),
            ])
        }
    }

    private func sendEvent(_ payload: [String: Any]) {
        socketSendQueue.async { [weak self] in
            self?.sendEventOnQueue(payload)
        }
    }

    private func sendEventOnQueue(_ payload: [String: Any]) {
        guard let webSocketTask else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask.send(.string(text)) { [weak self] error in
            guard let self else { return }
            if let error, self.isRecordingRequested, self.fallbackProvider == nil {
                self.triggerFallback(reason: "socket_send_failed", underlyingError: error)
            }
        }
    }

    private func sendEvent(type: String, additionalFields: [String: Any] = [:]) {
        socketSendQueue.async { [weak self] in
            self?.sendEventOnQueue(type: type, additionalFields: additionalFields)
        }
    }

    private func sendEventOnQueue(type: String, additionalFields: [String: Any] = [:]) {
        var payload = additionalFields
        payload["type"] = type
        sendEventOnQueue(payload)
    }

    private func flushSocketSendQueue() {
        socketSendQueue.sync {}
    }

    private func triggerFallback(reason: String, underlyingError: Error?) {
        guard !hasFallenBack else { return }
        hasFallenBack = true
        isStreamingActive = false

        TranscriptionTelemetry.track("transcription_fallback_triggered", fields: [
            "reason": reason,
        ])

        shutdownStreamingConnection()
        stopAudioCapture()
        finishRecordingFileWrites()

        guard isRecordingRequested else { return }

        let fallback = OpenAITranscriptionProvider(
            client: supabase,
            functionNameOverride: fallbackFunctionName,
            initialTranscript: lastTranscript
        )

        fallback.onPartial = { [weak self] text in
            guard let self else { return }
            self.onPartial?(text)
        }

        fallback.onFinal = { [weak self] text in
            guard let self else { return }
            self.onFinal?(text)
        }

        fallback.onError = { [weak self] error in
            guard let self else { return }
            TranscriptionTelemetry.track("transcription_error", fields: [
                "transport": "polling",
                "message": error.localizedDescription,
            ])
            self.onError?(error)
        }

        fallbackProvider = fallback

        do {
            try fallback.start()
            TranscriptionTelemetry.track("transcription_transport", fields: [
                "value": "polling",
            ])
            if let underlyingError {
                TranscriptionTelemetry.track("transcription_error", fields: [
                    "transport": "streaming",
                    "message": underlyingError.localizedDescription,
                ])
            }
        } catch {
            onError?(error)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func prepareRecordingFileIfNeeded() throws {
        guard recordingPCMHandle == nil else { return }

        let url = makeRecordingURL(extension: "wav")
        let pcmURL = makeRecordingURL(extension: "pcm")
        FileManager.default.createFile(atPath: pcmURL.path, contents: nil)

        recordingURL = url
        recordingPCMURL = pcmURL
        recordingPCMHandle = try FileHandle(forWritingTo: pcmURL)
    }

    private func startAudioCapture() throws {
        guard !audioEngine.isRunning else { return }

        let inputNode = audioEngine.inputNode
        if inputNode.numberOfInputs == 0 {
            throw OpenAIStreamingTranscriptionError.audioInputUnavailable
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw OpenAIStreamingTranscriptionError.audioConverterUnavailable
        }

        if !isTapInstalled {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                self.processInputBuffer(buffer, from: inputFormat, to: targetFormat)
            }
            isTapInstalled = true
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var error: NSError?
        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }

            provided = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        guard status != .error, error == nil else {
            return
        }

        if convertedBuffer.frameLength == 0 {
            return
        }

        guard let channelData = convertedBuffer.int16ChannelData else { return }
        let frameLength = Int(convertedBuffer.frameLength)
        let sampleCount = frameLength * Int(targetFormat.channelCount)
        let data = Data(bytes: channelData.pointee, count: sampleCount * MemoryLayout<Int16>.size)
        enqueueRecordingWrite(data: data)
        sendAudioChunk(data)
    }

    private func enqueueRecordingWrite(data: Data) {
        recordingWriteQueue.async { [weak self] in
            guard let self, let recordingPCMHandle = self.recordingPCMHandle else { return }
            if #available(iOS 13.4, *) {
                try? recordingPCMHandle.write(contentsOf: data)
            } else {
                recordingPCMHandle.write(data)
            }
        }
    }

    private func finishRecordingFileWrites() {
        recordingWriteQueue.sync {
            if #available(iOS 13.0, *) {
                try? recordingPCMHandle?.close()
            } else {
                recordingPCMHandle?.closeFile()
            }
            recordingPCMHandle = nil

            guard let recordingPCMURL, let recordingURL else { return }
            self.recordingPCMURL = nil
            do {
                try finalizeWAVFile(fromPCMAt: recordingPCMURL, toWAVAt: recordingURL)
            } catch {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            try? FileManager.default.removeItem(at: recordingPCMURL)
        }
    }

    private func shutdownStreamingConnection() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
    }

    private func makeRecordingURL() -> URL {
        makeRecordingURL(extension: "wav")
    }

    private func makeRecordingURL(extension ext: String) -> URL {
        let filename = "recording-stream-\(UUID().uuidString).\(ext)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func finalizeWAVFile(fromPCMAt pcmURL: URL, toWAVAt wavURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: pcmURL.path)
        let pcmByteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard pcmByteCount > 0 else { return }

        FileManager.default.createFile(atPath: wavURL.path, contents: nil)
        let wavHandle = try FileHandle(forWritingTo: wavURL)
        defer {
            if #available(iOS 13.0, *) {
                try? wavHandle.close()
            } else {
                wavHandle.closeFile()
            }
        }

        let header = makeWAVHeader(
            pcmByteCount: pcmByteCount,
            sampleRate: Int(sampleRate),
            channels: Int(channelCount),
            bitsPerSample: 16
        )

        if #available(iOS 13.4, *) {
            try wavHandle.write(contentsOf: header)
        } else {
            wavHandle.write(header)
        }

        let pcmHandle = try FileHandle(forReadingFrom: pcmURL)
        defer {
            if #available(iOS 13.0, *) {
                try? pcmHandle.close()
            } else {
                pcmHandle.closeFile()
            }
        }

        while true {
            let chunk: Data
            if #available(iOS 13.4, *) {
                chunk = try pcmHandle.read(upToCount: 64 * 1024) ?? Data()
            } else {
                chunk = pcmHandle.readData(ofLength: 64 * 1024)
            }

            if chunk.isEmpty {
                break
            }

            if #available(iOS 13.4, *) {
                try wavHandle.write(contentsOf: chunk)
            } else {
                wavHandle.write(chunk)
            }
        }
    }

    private func makeWAVHeader(
        pcmByteCount: Int,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) -> Data {
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let riffChunkSize = UInt32(36 + pcmByteCount)
        let dataChunkSize = UInt32(pcmByteCount)
        let audioFormat: UInt16 = 1

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.appendLE32(riffChunkSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.appendLE32(16)
        header.appendLE16(audioFormat)
        header.appendLE16(UInt16(channels))
        header.appendLE32(UInt32(sampleRate))
        header.appendLE32(byteRate)
        header.appendLE16(blockAlign)
        header.appendLE16(UInt16(bitsPerSample))
        header.append("data".data(using: .ascii)!)
        header.appendLE32(dataChunkSize)
        return header
    }

    private func normalizeTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalized = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
        guard let regex = try? NSRegularExpression(pattern: "([.!?])\\s+") else {
            return normalized
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.stringByReplacingMatches(
            in: normalized,
            options: [],
            range: range,
            withTemplate: "$1\n"
        )
    }

    private func combineTranscript(committed: String, current: String) -> String {
        let trimmedCommitted = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedCommitted.isEmpty { return trimmedCurrent }
        if trimmedCurrent.isEmpty { return trimmedCommitted }
        return "\(trimmedCommitted)\n\(trimmedCurrent)"
    }

    private func bestKnownTranscript() -> String {
        if !lastTranscript.isEmpty {
            return lastTranscript
        }

        let partialId = activePartialItemId ?? Array(partialTranscripts.keys).last
        let partial = partialId.flatMap { partialTranscripts[$0] } ?? ""
        return combineTranscript(
            committed: committedTranscript,
            current: normalizeTranscript(partial)
        )
    }

    private func trackFirstPartialIfNeeded(transport: String) {
        guard !hasTrackedFirstPartial else { return }
        hasTrackedFirstPartial = true
        let elapsedMs = Int((Date().timeIntervalSince(sessionStartedAt ?? Date())) * 1000)
        TranscriptionTelemetry.track("transcription_first_partial_ms", fields: [
            "transport": transport,
            "value": "\(max(elapsedMs, 0))",
        ])
    }

    private func registerLifecycleObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.isRecordingRequested, self.fallbackProvider == nil else { return }
            self.shouldReconnectAfterForeground = true
            self.sendEvent(type: "input_audio_buffer.commit")
            self.stopAudioCapture()
            self.shutdownStreamingConnection()
            self.isStreamingActive = false
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.isRecordingRequested, self.fallbackProvider == nil, self.shouldReconnectAfterForeground else { return }
            self.shouldReconnectAfterForeground = false
            Task {
                await self.startStreamingSession()
            }
        }
    }
}

private struct StreamSessionRequest: Encodable {
    let model: String
}

private struct StreamSessionResponse: Decodable {
    let value: String?
    let expiresAt: Int?
    let clientSecret: StreamClientSecret?

    enum CodingKeys: String, CodingKey {
        case value
        case expiresAt = "expires_at"
        case clientSecret = "client_secret"
    }
}

private struct StreamClientSecret: Decodable {
    let value: String
    let expiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case value
        case expiresAt = "expires_at"
    }
}

private enum OpenAIStreamingTranscriptionError: LocalizedError {
    case missingSupabaseConfig
    case invalidSessionResponse
    case audioInputUnavailable
    case audioConverterUnavailable
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .missingSupabaseConfig:
            return "Supabase configuration is missing. Check SUPABASE_URL and SUPABASE_ANON_KEY."
        case .invalidSessionResponse:
            return "OpenAI realtime session setup failed. Missing client secret from relay function."
        case .audioInputUnavailable:
            return "Audio input is unavailable for streaming transcription."
        case .audioConverterUnavailable:
            return "Unable to create audio converter for streaming transcription."
        case .provider(let message):
            return message
        }
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendLE32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }
}
