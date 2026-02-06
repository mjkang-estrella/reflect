import Foundation
import Supabase

struct ProfileMemoryRequest: Encodable {
    let sessionId: UUID
    let transcript: String
    let summary: SummaryPayload
}

struct ProfileMemoryUpdatedProfile: Decodable {
    let displayName: String
    let tone: String
    let proactivity: String
    let avoidTopics: String

    func toProfileSettings(fallback: ProfileSettings) -> ProfileSettings {
        ProfileSettings(
            displayName: displayName,
            tone: Tone(rawValue: tone) ?? fallback.tone,
            proactivity: Proactivity(rawValue: proactivity) ?? fallback.proactivity,
            avoidTopics: avoidTopics,
            schemaVersion: fallback.schemaVersion,
            name: fallback.name,
            pronouns: fallback.pronouns,
            timezone: fallback.timezone,
            notes: fallback.notes,
            lastUpdatedBy: fallback.lastUpdatedBy,
            lastUpdatedAt: fallback.lastUpdatedAt
        )
    }
}

struct ProfileMemoryResponse: Decodable {
    let applied: Bool
    let reason: String
    let updatedProfile: ProfileMemoryUpdatedProfile
    let sessionId: UUID
}

struct ProfileMemoryService {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) throws {
        if let client {
            self.client = client
        } else {
            self.client = try SupabaseClientProvider.makeClient()
        }
    }

    func updateFromSession(
        sessionId: UUID,
        transcript: String,
        summary: SummaryPayload?
    ) async throws -> ProfileMemoryResponse {
        let normalizedSummary = summary ?? SummaryPayload(headline: "", bullets: [])
        let request = ProfileMemoryRequest(
            sessionId: sessionId,
            transcript: transcript,
            summary: normalizedSummary
        )

        let accessToken = try await client.auth.session.accessToken
        let options = FunctionInvokeOptions(
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: request
        )

        return try await client.functions.invoke("profile-memory", options: options)
    }
}
