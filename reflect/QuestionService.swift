import Foundation
import Supabase

struct QuestionService {
    private let client: SupabaseClient
    private let functionName = "questions"

    init(client: SupabaseClient) {
        self.client = client
    }

    func validateAnswer(request: QuestionRequest) async throws -> QuestionResponse {
        try await client.functions.invoke(
            functionName,
            options: FunctionInvokeOptions(body: request)
        )
    }

    func requestNextQuestion(request: QuestionRequest) async throws -> QuestionResponse {
        try await client.functions.invoke(
            functionName,
            options: FunctionInvokeOptions(body: request)
        )
    }
}

struct QuestionRequest: Encodable {
    let mode: String
    let draftText: String
    let recentText: String
    let lastQuestion: String?
    let questionHistory: [QuestionHistoryItem]
    let profile: QuestionProfilePayload
    let recentSessions: [RecentSessionContext]
    let preferredKind: QuestionKind?
}

struct QuestionProfilePayload: Encodable {
    let tone: Tone
    let proactivity: Proactivity
    let avoidTopics: [String]
}

struct QuestionResponse: Decodable {
    let answered: Bool?
    let answerConfidence: Double?
    let nextQuestion: QuestionPayload?
    let reason: String?
    let fallbackUsed: Bool?
}

struct QuestionPayload: Decodable {
    let text: String
    let coverageTag: String?
    let kind: QuestionKind?
}
