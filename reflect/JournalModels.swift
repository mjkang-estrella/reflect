import Foundation

struct JournalSessionRecord: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    let endedAt: Date?
    let status: String
    let mode: String
    let title: String?
    let finalText: String?
    let durationSeconds: Int?
    let tags: [String]?
    let mood: String?
    let isFavorite: Bool
    let audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case mode
        case title
        case finalText = "final_text"
        case durationSeconds = "duration_seconds"
        case tags
        case mood
        case isFavorite = "is_favorite"
        case audioUrl = "audio_url"
    }
}

struct NewJournalSession: Encodable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    let endedAt: Date?
    let status: String
    let mode: String
    let title: String?
    let finalText: String?
    let durationSeconds: Int?
    let tags: [String]
    let mood: String?
    let isFavorite: Bool
    let audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case mode
        case title
        case finalText = "final_text"
        case durationSeconds = "duration_seconds"
        case tags
        case mood
        case isFavorite = "is_favorite"
        case audioUrl = "audio_url"
    }
}

struct NewJournalEntry: Encodable {
    let sessionId: UUID
    let createdAt: Date
    let text: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case createdAt = "created_at"
        case text
        case source
    }
}

struct SummaryPayload: Codable, Equatable, Hashable {
    let headline: String
    let bullets: [String]
}

struct DailySummaryRecord: Decodable {
    let sessionId: UUID
    let createdAt: Date
    let summaryJson: SummaryPayload

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case createdAt = "created_at"
        case summaryJson = "summary_json"
    }
}

struct NewSessionQuestion: Encodable {
    let id: UUID
    let sessionId: UUID
    let createdAt: Date?
    let question: String
    let coverageTag: String?
    let status: String
    let answeredText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case createdAt = "created_at"
        case question
        case coverageTag = "coverage_tag"
        case status
        case answeredText = "answered_text"
    }
}

struct NewTranscriptChunk: Encodable {
    let sessionId: UUID
    let createdAt: Date
    let text: String
    let confidence: Double?
    let provider: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case createdAt = "created_at"
        case text
        case confidence
        case provider
    }
}
