import Foundation
import Supabase

struct QuestionService {
    private let client: SupabaseClient
    private let functionName = "questions"

    init(client: SupabaseClient) {
        self.client = client
    }

    func validateAnswer(request: QuestionRequest) async throws -> QuestionResponse {
        try await invokeWithAuth(request: request)
    }

    func requestNextQuestion(request: QuestionRequest) async throws -> QuestionResponse {
        try await invokeWithAuth(request: request)
    }

    private func invokeWithAuth(request: QuestionRequest) async throws -> QuestionResponse {
        do {
            return try await invoke(request: request)
        } catch let functionsError as FunctionsError {
            guard isUnauthorized(functionsError) else {
                throw functionsError
            }

            _ = try await client.auth.refreshSession()
            return try await invoke(request: request)
        }
    }

    private func invoke(request: QuestionRequest) async throws -> QuestionResponse {
        let accessToken = try await client.auth.session.accessToken
        let options = FunctionInvokeOptions(
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: request
        )

        return try await client.functions.invoke(functionName, options: options)
    }

    private func isUnauthorized(_ error: FunctionsError) -> Bool {
        guard case let .httpError(code, _) = error else { return false }
        return code == 401
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
