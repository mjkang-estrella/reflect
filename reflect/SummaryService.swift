import Foundation
import Supabase

struct SummaryRequest: Encodable {
    let sessionId: UUID
    let transcript: String
    let title: String?
}

struct SummaryResponse: Decodable {
    let summary: SummaryPayload
}

struct SummaryService {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) throws {
        if let client {
            self.client = client
        } else {
            self.client = try SupabaseClientProvider.makeClient()
        }
    }

    func generateSummary(sessionId: UUID, transcript: String, title: String?) async throws -> SummaryPayload {
        let request = SummaryRequest(sessionId: sessionId, transcript: transcript, title: title)
        let accessToken = try await client.auth.session.accessToken
        let options = FunctionInvokeOptions(
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: request
        )

        let response: SummaryResponse = try await client.functions.invoke("summaries", options: options)
        return response.summary
    }
}
