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
    @Published private(set) var currentQuestion: QuestionItem?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private(set) var isSaving = false

    private let provider: TranscriptionProvider
    private let questionEngine = QuestionEngine()
    private let questionService: QuestionService?
    private var hasSpeechPermission = false
    private var hasMicPermission = false
    private var sessionStartedAt: Date?
    private var activeRecordingStart: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var sessionId: UUID?
    private var profile: ProfileSettings = .empty
    private var recentSessions: [RecentSessionContext] = []
    private var silenceTimer: DispatchSourceTimer?
    private var isRequestingQuestion = false
    private var isValidatingAnswer = false
    private var activeUserId: UUID?
    private var shouldDeleteDraftSession = false

    init(provider: TranscriptionProvider? = nil) {
        self.provider = provider ?? OpenAITranscriptionProvider()
        if let supabase = try? SupabaseClientProvider.makeClient() {
            self.questionService = QuestionService(client: supabase)
        } else {
            self.questionService = nil
        }
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

    func startRecording(userId: UUID? = nil) {
        if let userId {
            activeUserId = userId
        }
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
                startSilenceTimer()
                await startSessionIfNeeded()
            } catch {
                handleError(error)
            }
        }
    }

    func pauseRecording() {
        provider.stop()
        accumulateDuration()
        state = .paused
        stopSilenceTimer()
    }

    func resumeRecording() {
        startRecording(userId: activeUserId)
    }

    func stopAndReset() {
        provider.cancel()
        stopSilenceTimer()
        transcriptText = ""
        committedLines = []
        currentLine = ""
        currentQuestion = nil
        state = .idle
        sessionStartedAt = nil
        activeRecordingStart = nil
        accumulatedDuration = 0
        isRequestingQuestion = false
        isValidatingAnswer = false
        if shouldDeleteDraftSession, let sessionId {
            Task {
                do {
                    let repository = try JournalRepository()
                    try await repository.deleteSession(sessionId: sessionId)
                } catch {
                    self.handleError(error)
                }
            }
        }
        sessionId = nil
        shouldDeleteDraftSession = false
        questionEngine.reset()
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
        processTranscriptUpdate()
    }

    private func handleFinal(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            updateTranscript(with: text, finalizeCurrentLine: true)
        }
        processTranscriptUpdate()
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

    func saveRecording(userId: UUID) async -> Bool {
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
            if sessionId == nil {
                sessionId = try await repository.startVoiceSession(userId: userId, startedAt: startedAt)
            }
            if let sessionId {
                try await repository.completeVoiceSession(
                    sessionId: sessionId,
                    transcript: trimmed,
                    durationSeconds: durationSeconds == 0 ? nil : durationSeconds,
                    startedAt: startedAt,
                    endedAt: endedAt
                )
            }
            shouldDeleteDraftSession = false
            NotificationCenter.default.post(name: .journalEntriesDidChange, object: nil)
            return true
        } catch {
            presentError(error.localizedDescription)
            return false
        }
    }

    func refreshQuestion() {
        guard sessionId != nil, let currentQuestion else { return }
        updateQuestionStatus(.ignored)
        Task {
            do {
                let repository = try JournalRepository()
                try await repository.updateSessionQuestion(
                    questionId: currentQuestion.id,
                    status: QuestionStatus.ignored.rawValue,
                    answeredText: nil
                )
            } catch {
                self.handleError(error)
            }
        }
        let recentText = questionEngine.buildRecentText(
            committedLines: committedLines,
            currentLine: currentLine
        )
        requestNextQuestion(reason: .refresh, recentText: recentText)
    }

    private func processTranscriptUpdate() {
        guard state == .recording else { return }
        let action = questionEngine.evaluateTranscript(
            fullText: transcriptText,
            committedLines: committedLines,
            currentLine: currentLine,
            now: Date(),
            proactivity: profile.proactivity
        )
        if let action {
            handleQuestionAction(action)
        }
    }

    private func handleQuestionAction(_ action: QuestionEngineAction) {
        switch action {
        case .validateAnswer(let recentText):
            validateAnswer(recentText: recentText)
        case .requestNextQuestion(let reason, let recentText):
            requestNextQuestion(reason: reason, recentText: recentText)
        }
    }

    private func validateAnswer(recentText: String) {
        guard !isValidatingAnswer else { return }
        guard let questionService else { return }
        guard currentQuestion != nil else { return }
        guard sessionId != nil else { return }

        isValidatingAnswer = true
        updateQuestionStatus(.pendingValidation)

        Task {
            defer { self.isValidatingAnswer = false }
            do {
                let request = buildQuestionRequest(
                    mode: "validate",
                    recentText: recentText,
                    preferredKind: nil
                )
                let response = try await questionService.validateAnswer(request: request)
                let answered = response.answered ?? false
                if answered {
                    updateQuestionStatus(.answered)
                    let repository = try JournalRepository()
                    if let questionId = self.currentQuestion?.id {
                        try await repository.updateSessionQuestion(
                            questionId: questionId,
                            status: QuestionStatus.answered.rawValue,
                            answeredText: recentText
                        )
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.requestNextQuestion(reason: .answered, recentText: recentText)
                    }
                } else {
                    updateQuestionStatus(.shown)
                }
            } catch {
                updateQuestionStatus(.shown)
                self.handleError(error)
            }
        }
    }

    private func requestNextQuestion(reason: QuestionTriggerReason, recentText: String) {
        guard !isRequestingQuestion else { return }
        guard sessionId != nil else { return }

        isRequestingQuestion = true
        let preferredKind = questionEngine.preferredNextKind(reason: reason)

        Task {
            defer { self.isRequestingQuestion = false }
            guard let questionService else {
                let fallback = fallbackQuestion(kind: preferredKind)
                await applyNextQuestion(fallback)
                return
            }
            let response: QuestionResponse
            do {
                let request = buildQuestionRequest(
                    mode: "next",
                    recentText: recentText,
                    preferredKind: preferredKind
                )
                response = try await questionService.requestNextQuestion(request: request)
            } catch {
                let fallback = fallbackQuestion(kind: preferredKind)
                await applyNextQuestion(fallback)
                self.handleError(error)
                return
            }

            if let payload = response.nextQuestion {
                let question = QuestionItem(
                    id: UUID(),
                    text: payload.text,
                    coverageTag: payload.coverageTag,
                    kind: payload.kind ?? preferredKind,
                    status: .shown,
                    askedAt: Date()
                )
                await applyNextQuestion(question)
            } else {
                let fallback = fallbackQuestion(kind: preferredKind)
                await applyNextQuestion(fallback)
            }
        }
    }

    private func applyNextQuestion(_ question: QuestionItem?) async {
        guard let question else { return }
        let wordCount = transcriptText.split { !$0.isLetter && !$0.isNumber }.count
        questionEngine.setCurrentQuestion(question, wordCount: wordCount, now: question.askedAt)
        currentQuestion = question

        guard let sessionId else { return }
        do {
            let repository = try JournalRepository()
            let newQuestion = NewSessionQuestion(
                id: question.id,
                sessionId: sessionId,
                createdAt: question.askedAt,
                question: question.text,
                coverageTag: question.coverageTag,
                status: QuestionStatus.shown.rawValue,
                answeredText: nil
            )
            try await repository.insertSessionQuestion(newQuestion)
        } catch {
            handleError(error)
        }
    }

    private func fallbackQuestion(kind: QuestionKind) -> QuestionItem? {
        let avoidTopics = avoidTopicsList(from: profile.avoidTopics)
        let excludingTags = Set(questionEngine.questionHistory.suffix(2).compactMap { $0.coverageTag })
        guard let template = QuestionPool.shared.randomQuestion(
            avoidTopics: avoidTopics,
            excludingTags: excludingTags
        ) else { return nil }
        return QuestionItem(
            id: UUID(),
            text: template.text,
            coverageTag: template.coverageTag,
            kind: kind,
            status: .shown,
            askedAt: Date()
        )
    }

    private func updateQuestionStatus(_ status: QuestionStatus) {
        questionEngine.updateCurrentQuestionStatus(status)
        currentQuestion = questionEngine.currentQuestion
    }

    private func buildQuestionRequest(mode: String, recentText: String, preferredKind: QuestionKind?) -> QuestionRequest {
        let history = questionEngine.questionHistory.map { item in
            QuestionHistoryItem(
                text: item.text,
                coverageTag: item.coverageTag,
                kind: item.kind,
                status: item.status
            )
        }
        return QuestionRequest(
            mode: mode,
            draftText: transcriptText,
            recentText: recentText,
            lastQuestion: questionEngine.currentQuestion?.text,
            questionHistory: history,
            profile: QuestionProfilePayload(
                tone: profile.tone,
                proactivity: profile.proactivity,
                avoidTopics: avoidTopicsList(from: profile.avoidTopics)
            ),
            recentSessions: recentSessions,
            preferredKind: preferredKind
        )
    }

    private func startSilenceTimer() {
        stopSilenceTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .recording else { return }
            if let action = self.questionEngine.evaluateSilence(
                fullText: self.transcriptText,
                committedLines: self.committedLines,
                currentLine: self.currentLine,
                now: Date(),
                proactivity: self.profile.proactivity
            ) {
                self.handleQuestionAction(action)
            }
        }
        silenceTimer = timer
        timer.resume()
    }

    private func stopSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }

    private func startSessionIfNeeded() async {
        guard sessionId == nil else { return }
        guard let userId = activeUserId else { return }

        do {
            let repository = try JournalRepository()
            let startedAt = sessionStartedAt ?? Date()
            let id = try await repository.startVoiceSession(userId: userId, startedAt: startedAt)
            sessionId = id
            shouldDeleteDraftSession = true
            await loadQuestionContext(userId: userId)
            await showInitialQuestion()
        } catch {
            handleError(error)
        }
    }

    private func loadQuestionContext(userId: UUID) async {
        do {
            let profileRepository = try ProfileRepository()
            if let fetched = try await profileRepository.fetchProfile(userId: userId) {
                profile = fetched
            } else {
                profile = .empty
            }
        } catch {
            profile = .empty
        }

        do {
            let repository = try JournalRepository()
            let sessions = try await repository.fetchSessions(userId: userId)
            let summaries = sessions
                .filter { $0.status == "completed" }
                .prefix(3)
                .map { session in
                    RecentSessionContext(
                        title: session.title ?? "",
                        snippet: String((session.finalText ?? "").prefix(280))
                    )
                }
            recentSessions = summaries
        } catch {
            recentSessions = []
        }
    }

    private func showInitialQuestion() async {
        guard currentQuestion == nil else { return }
        let avoidTopics = avoidTopicsList(from: profile.avoidTopics)
        guard let template = QuestionPool.shared.randomQuestion(avoidTopics: avoidTopics) else { return }
        let question = QuestionItem(
            id: UUID(),
            text: template.text,
            coverageTag: template.coverageTag,
            kind: .default,
            status: .shown,
            askedAt: Date()
        )
        await applyNextQuestion(question)
    }

    private func avoidTopicsList(from raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
