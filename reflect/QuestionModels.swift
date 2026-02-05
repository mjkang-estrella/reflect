import Foundation

enum QuestionKind: String, Codable {
    case `default`
    case followUp = "follow_up"
    case newTopic = "new_topic"
}

enum QuestionStatus: String, Codable {
    case shown
    case answered
    case ignored
    case pendingValidation = "pending_validation"
}

struct QuestionItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let coverageTag: String?
    let kind: QuestionKind
    var status: QuestionStatus
    let askedAt: Date
}

struct QuestionHistoryItem: Encodable {
    let text: String
    let coverageTag: String?
    let kind: QuestionKind
    let status: QuestionStatus
}

struct RecentSessionContext: Encodable, Equatable {
    let title: String
    let snippet: String
}
