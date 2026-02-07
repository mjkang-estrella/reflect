import AVFoundation
import Combine
import Foundation
import Speech
import Supabase
import SwiftUI

protocol ChatQuestionServicing {
    func validateAnswer(request: QuestionRequest) async throws -> QuestionResponse
    func requestNextQuestion(request: QuestionRequest) async throws -> QuestionResponse
}

extension QuestionService: ChatQuestionServicing {}

protocol ChatJournalRepository {
    func fetchSessions(userId: UUID) async throws -> [JournalSessionRecord]
    func startTextSession(userId: UUID, startedAt: Date) async throws -> UUID
    func completeTextSession(sessionId: UUID, transcript: String, startedAt: Date, endedAt: Date) async throws
    func deleteSession(sessionId: UUID) async throws
    func insertSessionQuestion(_ question: NewSessionQuestion) async throws
    func updateSessionQuestion(questionId: UUID, status: String, answeredText: String?) async throws
    func updateTitle(sessionId: UUID, title: String) async throws
}

extension JournalRepository: ChatJournalRepository {}

protocol ChatProfileRepository {
    func fetchProfile(userId: UUID) async throws -> ProfileSettings?
}

extension ProfileRepository: ChatProfileRepository {}

protocol ChatSummaryServicing {
    func generateSummary(sessionId: UUID, transcript: String, title: String?) async throws -> SummaryPayload
}

extension SummaryService: ChatSummaryServicing {}

protocol ChatProfileMemoryServicing {
    func updateFromSession(
        sessionId: UUID,
        transcript: String,
        summary: SummaryPayload?
    ) async throws -> ProfileMemoryResponse
}

extension ProfileMemoryService: ChatProfileMemoryServicing {}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draftText: String = ""
    @Published private(set) var currentQuestion: QuestionItem?
    @Published private(set) var isListening = false
    @Published private(set) var isSaving = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let questionEngine: QuestionEngine
    private let questionService: (any ChatQuestionServicing)?
    private let repositoryFactory: () throws -> any ChatJournalRepository
    private let profileRepositoryFactory: () throws -> any ChatProfileRepository
    private let summaryServiceFactory: () throws -> any ChatSummaryServicing
    private let profileMemoryServiceFactory: () throws -> any ChatProfileMemoryServicing
    private let transcriptionProviderFactory: () -> TranscriptionProvider

    private var activeProvider: TranscriptionProvider?

    private var hasSpeechPermission = false
    private var hasMicPermission = false

    private var sessionId: UUID?
    private var sessionStartedAt: Date?
    private var shouldDeleteDraftSession = false

    private var profile: ProfileSettings = .empty
    private var recentSessions: [RecentSessionContext] = []

    private var userTranscriptLines: [String] = []

    private var isRequestingQuestion = false
    private var isValidatingAnswer = false

    init(
        questionEngine: QuestionEngine? = nil,
        questionService: (any ChatQuestionServicing)? = nil,
        repositoryFactory: (() throws -> any ChatJournalRepository)? = nil,
        profileRepositoryFactory: (() throws -> any ChatProfileRepository)? = nil,
        summaryServiceFactory: (() throws -> any ChatSummaryServicing)? = nil,
        profileMemoryServiceFactory: (() throws -> any ChatProfileMemoryServicing)? = nil,
        transcriptionProviderFactory: (() -> TranscriptionProvider)? = nil
    ) {
        self.questionEngine = questionEngine ?? QuestionEngine()
        self.questionService = questionService ?? ChatViewModel.makeDefaultQuestionService()
        self.repositoryFactory = repositoryFactory ?? { try JournalRepository() }
        self.profileRepositoryFactory = profileRepositoryFactory ?? { try ProfileRepository() }
        self.summaryServiceFactory = summaryServiceFactory ?? { try SummaryService() }
        self.profileMemoryServiceFactory = profileMemoryServiceFactory ?? { try ProfileMemoryService() }
        self.transcriptionProviderFactory = transcriptionProviderFactory
            ?? { ChatViewModel.makeDefaultTranscriptionProvider() }
    }

    var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSave: Bool {
        !userTranscriptText().isEmpty && !isSaving
    }

    var hasUnsavedContent: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !userTranscriptLines.isEmpty
            || shouldDeleteDraftSession
    }

    func sendDraft(userId: UUID?) async {
        guard let userId else {
            presentError("Sign in to chat.")
            return
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isListening {
            stopDictation()
        }

        do {
            try await ensureSessionReady(userId: userId)
        } catch {
            handleError(error)
            return
        }

        draftText = ""
        userTranscriptLines.append(trimmed)
        messages.append(ChatMessage(role: .user, text: trimmed))

        await evaluateLatestMessage(trimmed)
    }

    func refreshQuestion() async {
        guard sessionId != nil, let currentQuestion else { return }
        updateQuestionStatus(.ignored)

        do {
            let repository = try repositoryFactory()
            try await repository.updateSessionQuestion(
                questionId: currentQuestion.id,
                status: QuestionStatus.ignored.rawValue,
                answeredText: nil
            )
        } catch {
            handleError(error)
        }

        let recentText = questionEngine.buildRecentText(committedLines: userTranscriptLines, currentLine: "")
        await requestNextQuestion(reason: .refresh, recentText: recentText)
    }

    func saveSession(userId: UUID?) async -> JournalEntry? {
        guard let userId else {
            presentError("Sign in to save this chat.")
            return nil
        }

        let transcript = userTranscriptText()
        guard !transcript.isEmpty else {
            presentError("Write something before saving.")
            return nil
        }

        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }

        do {
            try await ensureSessionReady(userId: userId)
        } catch {
            presentError(error.localizedDescription)
            return nil
        }

        guard let sessionId else { return nil }

        let startedAt = sessionStartedAt ?? Date()
        let endedAt = Date()

        do {
            let repository = try repositoryFactory()
            try await repository.completeTextSession(
                sessionId: sessionId,
                transcript: transcript,
                startedAt: startedAt,
                endedAt: endedAt
            )

            var generatedSummary: SummaryPayload?
            var resolvedTitle: String?
            do {
                let summaryService = try summaryServiceFactory()
                let summary = try await summaryService.generateSummary(
                    sessionId: sessionId,
                    transcript: transcript,
                    title: nil
                )
                generatedSummary = summary

                let headline = summary.headline.trimmingCharacters(in: .whitespacesAndNewlines)
                if !headline.isEmpty {
                    resolvedTitle = headline
                    do {
                        try await repository.updateTitle(sessionId: sessionId, title: headline)
                    } catch {
                        // Keep save successful even if title update fails.
                    }
                }
            } catch {
                // Summary generation is best-effort.
            }

            do {
                let profileMemoryService = try profileMemoryServiceFactory()
                let memoryResponse = try await profileMemoryService.updateFromSession(
                    sessionId: sessionId,
                    transcript: transcript,
                    summary: generatedSummary
                )
                applyUpdatedProfile(memoryResponse.updatedProfile)
            } catch {
                // Profile memory update is best-effort.
            }

            shouldDeleteDraftSession = false
            NotificationCenter.default.post(name: .journalEntriesDidChange, object: nil)

            return JournalEntry(
                id: sessionId,
                createdAt: startedAt,
                title: resolvedTitle ?? "",
                transcription: transcript,
                duration: 0,
                tags: [],
                mood: nil,
                isFavorite: false,
                audioUrl: nil,
                summary: generatedSummary
            )
        } catch {
            presentError(error.localizedDescription)
            return nil
        }
    }

    func toggleDictation() async {
        if isListening {
            stopDictation()
            return
        }

        let provider = transcriptionProviderFactory()
        let authorized = await requestPermissionsIfNeeded(for: provider)
        guard authorized else { return }

        provider.onPartial = { [weak self] text in
            Task { @MainActor in
                self?.draftText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        provider.onFinal = { [weak self] text in
            Task { @MainActor in
                self?.draftText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        provider.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleError(error)
            }
        }

        do {
            try provider.start()
            activeProvider = provider
            isListening = true
        } catch {
            handleError(error)
        }
    }

    func stopDictation() {
        activeProvider?.stop()
        activeProvider = nil
        isListening = false
    }

    func cleanupOnDisappear() {
        activeProvider?.cancel()
        activeProvider = nil
        isListening = false
    }

    func discardDraftIfNeeded() async {
        cleanupOnDisappear()

        if shouldDeleteDraftSession, let sessionId {
            do {
                let repository = try repositoryFactory()
                try await repository.deleteSession(sessionId: sessionId)
            } catch {
                handleError(error)
            }
        }

        resetLocalState()
    }

    private func evaluateLatestMessage(_ message: String) async {
        guard currentQuestion != nil else { return }

        var linesForEvaluation = userTranscriptLines
        if !messageEndsAtSentenceBoundary(message), var last = linesForEvaluation.popLast() {
            last += "."
            linesForEvaluation.append(last)
        }

        if let action = questionEngine.evaluateTranscript(
            fullText: userTranscriptText(),
            committedLines: linesForEvaluation,
            currentLine: "",
            now: Date(),
            proactivity: profile.proactivity
        ) {
            await handleQuestionAction(action)
        }
    }

    private func messageEndsAtSentenceBoundary(_ message: String) -> Bool {
        guard let last = message.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return last == "." || last == "?" || last == "!"
    }

    private func handleQuestionAction(_ action: QuestionEngineAction) async {
        switch action {
        case .validateAnswer(let recentText):
            await validateAnswer(recentText: recentText)
        case .requestNextQuestion(let reason, let recentText):
            await requestNextQuestion(reason: reason, recentText: recentText)
        }
    }

    private func validateAnswer(recentText: String) async {
        guard !isValidatingAnswer else { return }
        guard currentQuestion != nil else { return }
        guard sessionId != nil else { return }

        isValidatingAnswer = true
        updateQuestionStatus(.pendingValidation)
        defer { isValidatingAnswer = false }

        guard let questionService else {
            await markAnswered(recentText: recentText)
            return
        }

        do {
            let request = buildQuestionRequest(mode: "validate", recentText: recentText, preferredKind: nil)
            let response = try await questionService.validateAnswer(request: request)
            if response.answered ?? false {
                await markAnswered(recentText: recentText)
            } else {
                updateQuestionStatus(.shown)
            }
        } catch {
            updateQuestionStatus(.shown)
            handleNonFatalQuestionError(error, context: "validate")
        }
    }

    private func markAnswered(recentText: String) async {
        updateQuestionStatus(.answered)
        if let questionId = currentQuestion?.id {
            do {
                let repository = try repositoryFactory()
                try await repository.updateSessionQuestion(
                    questionId: questionId,
                    status: QuestionStatus.answered.rawValue,
                    answeredText: recentText
                )
            } catch {
                handleNonFatalQuestionError(error, context: "update_answered")
            }
        }
        await requestNextQuestion(reason: .answered, recentText: recentText)
    }

    private func requestNextQuestion(reason: QuestionTriggerReason, recentText: String) async {
        guard !isRequestingQuestion else { return }
        guard sessionId != nil else { return }

        isRequestingQuestion = true
        defer { isRequestingQuestion = false }

        let preferredKind = questionEngine.preferredNextKind(reason: reason)

        guard let questionService else {
            await applyNextQuestion(fallbackQuestion(kind: preferredKind))
            return
        }

        do {
            let request = buildQuestionRequest(
                mode: "next",
                recentText: recentText,
                preferredKind: preferredKind
            )
            let response = try await questionService.requestNextQuestion(request: request)
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
                await applyNextQuestion(fallbackQuestion(kind: preferredKind))
            }
        } catch {
            await applyNextQuestion(fallbackQuestion(kind: preferredKind))
            handleNonFatalQuestionError(error, context: "next")
        }
    }

    private func applyNextQuestion(_ question: QuestionItem?) async {
        guard let question else { return }

        let wordCount = userTranscriptText().split { !$0.isLetter && !$0.isNumber }.count
        questionEngine.setCurrentQuestion(question, wordCount: wordCount, now: question.askedAt)
        currentQuestion = question
        messages.append(ChatMessage(role: .assistant, text: question.text, createdAt: question.askedAt))

        guard let sessionId else { return }
        do {
            let repository = try repositoryFactory()
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
            handleNonFatalQuestionError(error, context: "persist")
        }
    }

    private func ensureSessionReady(userId: UUID) async throws {
        guard sessionId == nil else { return }

        let repository = try repositoryFactory()
        let startedAt = Date()
        let id = try await repository.startTextSession(userId: userId, startedAt: startedAt)
        sessionId = id
        sessionStartedAt = startedAt
        shouldDeleteDraftSession = true

        await loadQuestionContext(userId: userId)
        await showInitialQuestion()
    }

    private func loadQuestionContext(userId: UUID) async {
        do {
            let repository = try profileRepositoryFactory()
            if let fetched = try await repository.fetchProfile(userId: userId) {
                profile = fetched
            } else {
                profile = .empty
            }
        } catch {
            profile = .empty
        }

        do {
            let repository = try repositoryFactory()
            let sessions = try await repository.fetchSessions(userId: userId)
            recentSessions = sessions
                .filter { $0.status == "completed" }
                .map { session in
                    RecentSessionContext(
                        title: session.title ?? "",
                        snippet: String((session.finalText ?? "").prefix(280))
                    )
                }
        } catch {
            recentSessions = []
        }
    }

    private func showInitialQuestion() async {
        guard currentQuestion == nil else { return }
        let question = QuestionItem(
            id: UUID(),
            text: QuestionDefaults.firstQuestionText,
            coverageTag: QuestionDefaults.firstQuestionCoverageTag,
            kind: .default,
            status: .shown,
            askedAt: Date()
        )
        await applyNextQuestion(question)
    }

    private func fallbackQuestion(kind: QuestionKind) -> QuestionItem? {
        let avoidTopics = avoidTopicsList(from: profile.avoidTopics)
        let excludingTags = Set(questionEngine.questionHistory.suffix(2).compactMap { $0.coverageTag })

        guard let template = QuestionPool.shared.randomQuestion(
            avoidTopics: avoidTopics,
            excludingTags: excludingTags
        ) else {
            return nil
        }

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

    private func buildQuestionRequest(
        mode: String,
        recentText: String,
        preferredKind: QuestionKind?
    ) -> QuestionRequest {
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
            draftText: userTranscriptText(),
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

    private func avoidTopicsList(from raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func userTranscriptText() -> String {
        userTranscriptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleNonFatalQuestionError(_ error: Error, context: String) {
        var fields: [String: String] = [
            "context": context,
            "message": error.localizedDescription,
        ]
        if let functionsError = error as? FunctionsError,
           case let .httpError(code, _) = functionsError
        {
            fields["status"] = "\(code)"
        }
        TranscriptionTelemetry.track("chat_question_error_non_fatal", fields: fields)
    }

    private func requestPermissionsIfNeeded(for provider: TranscriptionProvider) async -> Bool {
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

    private func applyUpdatedProfile(_ updatedProfile: ProfileMemoryUpdatedProfile) {
        let merged = updatedProfile.toProfileSettings(fallback: profile)
        profile = merged

        let defaults = UserDefaults.standard
        defaults.set(merged.displayName, forKey: "onboardingDisplayName")
        defaults.set(merged.tone.rawValue, forKey: "onboardingTone")
        defaults.set(merged.proactivity.rawValue, forKey: "onboardingProactivity")
        defaults.set(merged.avoidTopics, forKey: "onboardingAvoidTopics")
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func resetLocalState() {
        messages = []
        draftText = ""
        currentQuestion = nil

        sessionId = nil
        sessionStartedAt = nil
        shouldDeleteDraftSession = false

        userTranscriptLines = []

        isRequestingQuestion = false
        isValidatingAnswer = false

        questionEngine.reset()
    }

    private static func makeDefaultTranscriptionProvider() -> TranscriptionProvider {
        let backend = TranscriptionRuntimeSettings.selectedBackend()
        if backend == .openAI, TranscriptionRuntimeSettings.isStreamingEnabled() {
            return OpenAIStreamingTranscriptionProvider()
        }

        return OpenAITranscriptionProvider()
    }

    private static func makeDefaultQuestionService() -> (any ChatQuestionServicing)? {
        guard let client = try? SupabaseClientProvider.makeClient() else {
            return nil
        }
        return QuestionService(client: client)
    }
}
