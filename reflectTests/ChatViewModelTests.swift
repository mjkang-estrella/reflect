import Foundation
import Testing
@testable import reflect

@MainActor
struct ChatViewModelTests {
    @Test func sendDraftStartsSessionAndAddsInitialAssistantQuestion() async {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.draftText = "I felt calm because I went for a walk."
        await viewModel.sendDraft(userId: context.userId)

        #expect(context.repository.startedSessionUserIds.count == 1)
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == .assistant)
        #expect(viewModel.messages[0].text == QuestionDefaults.firstQuestionText)
        #expect(viewModel.messages[1].role == .user)
    }

    @Test func answeredMessageRequestsNextFollowUp() async {
        let context = TestContext()
        context.questionService.validateResponse = QuestionResponse(
            answered: true,
            answerConfidence: 0.93,
            nextQuestion: nil,
            reason: "answered",
            fallbackUsed: false
        )
        context.questionService.nextResponse = QuestionResponse(
            answered: false,
            answerConfidence: nil,
            nextQuestion: QuestionPayload(
                text: "What mattered most about that moment?",
                coverageTag: "values",
                kind: .followUp
            ),
            reason: "generated",
            fallbackUsed: false
        )

        let viewModel = context.makeViewModel()
        viewModel.draftText = "I felt calm because I went for a walk."
        await viewModel.sendDraft(userId: context.userId)

        #expect(context.questionService.validateRequests.count == 1)
        #expect(context.questionService.nextRequests.count == 1)
        #expect(viewModel.currentQuestion?.text == "What mattered most about that moment?")
        #expect(viewModel.messages.count == 3)
        #expect(viewModel.messages.last?.role == .assistant)
    }

    @Test func refreshQuestionMarksIgnoredAndRequestsNewTopic() async {
        let context = TestContext()
        context.questionService.validateResponse = QuestionResponse(
            answered: false,
            answerConfidence: 0.12,
            nextQuestion: nil,
            reason: "not_answered",
            fallbackUsed: false
        )
        context.questionService.nextResponse = QuestionResponse(
            answered: false,
            answerConfidence: nil,
            nextQuestion: QuestionPayload(
                text: "What else felt important in your day?",
                coverageTag: "event",
                kind: nil
            ),
            reason: "generated",
            fallbackUsed: false
        )

        let viewModel = context.makeViewModel()
        viewModel.draftText = "Today was quiet and simple."
        await viewModel.sendDraft(userId: context.userId)
        await viewModel.refreshQuestion()

        #expect(context.repository.updatedQuestionStatuses.contains(QuestionStatus.ignored.rawValue))
        #expect(context.questionService.nextRequests.last?.preferredKind == .newTopic)
        #expect(viewModel.currentQuestion?.kind == .newTopic)
    }

    @Test func saveEmptyTranscriptShowsError() async {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        let entry = await viewModel.saveSession(userId: context.userId)

        #expect(entry == nil)
        #expect(viewModel.showError)
        #expect(viewModel.errorMessage == "Write something before saving.")
    }

    @Test func saveSessionPersistsTranscriptAndReturnsEntry() async {
        let context = TestContext()
        context.summaryService.summary = SummaryPayload(
            headline: "A Calm Walk",
            bullets: ["You slowed down and noticed what helped."]
        )

        let viewModel = context.makeViewModel()
        viewModel.draftText = "I felt better after taking a walk."
        await viewModel.sendDraft(userId: context.userId)

        let entry = await viewModel.saveSession(userId: context.userId)

        #expect(entry != nil)
        #expect(context.repository.completedTranscripts.count == 1)
        #expect(context.repository.completedTranscripts[0].contains("I felt better after taking a walk."))
        #expect(entry?.summary?.headline == "A Calm Walk")
        #expect(context.profileMemoryService.updatedSessionIds.count == 1)
    }
}

@MainActor
private final class TestContext {
    let userId = UUID()
    let repository = MockJournalRepository()
    let questionService = MockQuestionService()
    let profileRepository = MockProfileRepository()
    let summaryService = MockSummaryService()
    let profileMemoryService = MockProfileMemoryService()

    func makeViewModel() -> ChatViewModel {
        ChatViewModel(
            questionService: questionService,
            repositoryFactory: { self.repository },
            profileRepositoryFactory: { self.profileRepository },
            summaryServiceFactory: { self.summaryService },
            profileMemoryServiceFactory: { self.profileMemoryService },
            transcriptionProviderFactory: { MockTranscriptionProvider() }
        )
    }
}

private final class MockQuestionService: ChatQuestionServicing {
    var validateResponse = QuestionResponse(
        answered: false,
        answerConfidence: 0,
        nextQuestion: nil,
        reason: "default",
        fallbackUsed: false
    )
    var nextResponse = QuestionResponse(
        answered: false,
        answerConfidence: 0,
        nextQuestion: nil,
        reason: "default",
        fallbackUsed: false
    )

    private(set) var validateRequests: [QuestionRequest] = []
    private(set) var nextRequests: [QuestionRequest] = []

    func validateAnswer(request: QuestionRequest) async throws -> QuestionResponse {
        validateRequests.append(request)
        return validateResponse
    }

    func requestNextQuestion(request: QuestionRequest) async throws -> QuestionResponse {
        nextRequests.append(request)
        return nextResponse
    }
}

private final class MockJournalRepository: ChatJournalRepository {
    private(set) var startedSessionUserIds: [UUID] = []
    private(set) var completedTranscripts: [String] = []
    private(set) var deletedSessionIds: [UUID] = []
    private(set) var insertedQuestions: [NewSessionQuestion] = []
    private(set) var updatedQuestionStatuses: [String] = []
    private(set) var updatedTitles: [String] = []

    var nextSessionId = UUID()
    var sessions: [JournalSessionRecord] = []

    func fetchSessions(userId: UUID) async throws -> [JournalSessionRecord] {
        sessions
    }

    func startTextSession(userId: UUID, startedAt: Date) async throws -> UUID {
        startedSessionUserIds.append(userId)
        return nextSessionId
    }

    func completeTextSession(
        sessionId: UUID,
        transcript: String,
        startedAt: Date,
        endedAt: Date
    ) async throws {
        completedTranscripts.append(transcript)
    }

    func deleteSession(sessionId: UUID) async throws {
        deletedSessionIds.append(sessionId)
    }

    func insertSessionQuestion(_ question: NewSessionQuestion) async throws {
        insertedQuestions.append(question)
    }

    func updateSessionQuestion(questionId: UUID, status: String, answeredText: String?) async throws {
        updatedQuestionStatuses.append(status)
    }

    func updateTitle(sessionId: UUID, title: String) async throws {
        updatedTitles.append(title)
    }
}

private final class MockProfileRepository: ChatProfileRepository {
    var profile: ProfileSettings? = .empty

    func fetchProfile(userId: UUID) async throws -> ProfileSettings? {
        profile
    }
}

private final class MockSummaryService: ChatSummaryServicing {
    var summary = SummaryPayload(headline: "", bullets: [])

    func generateSummary(sessionId: UUID, transcript: String, title: String?) async throws -> SummaryPayload {
        summary
    }
}

private final class MockProfileMemoryService: ChatProfileMemoryServicing {
    private(set) var updatedSessionIds: [UUID] = []

    func updateFromSession(
        sessionId: UUID,
        transcript: String,
        summary: SummaryPayload?
    ) async throws -> ProfileMemoryResponse {
        updatedSessionIds.append(sessionId)
        return ProfileMemoryResponse(
            applied: true,
            reason: "ok",
            updatedProfile: ProfileMemoryUpdatedProfile(
                displayName: "Tester",
                tone: Tone.balanced.rawValue,
                proactivity: Proactivity.medium.rawValue,
                avoidTopics: ""
            ),
            sessionId: sessionId
        )
    }
}

private final class MockTranscriptionProvider: TranscriptionProvider {
    let requiresSpeechAuthorization = false
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var recordingFileURL: URL? { nil }

    func start() throws {}
    func stop() {}
    func cancel() {}
}
