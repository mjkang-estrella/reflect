import Foundation

enum QuestionDefaults {
    static let firstQuestionText = "How was your day"
    static let firstQuestionCoverageTag = "event"
}

struct QuestionTemplate: Equatable {
    let text: String
    let coverageTag: String
    let kind: QuestionKind
}

struct QuestionPool {
    static let shared = QuestionPool()

    private let questions: [QuestionTemplate] = [
        QuestionTemplate(text: "What felt most important today?", coverageTag: "values", kind: .default),
        QuestionTemplate(text: "What moment stayed with you the most?", coverageTag: "event", kind: .default),
        QuestionTemplate(text: "What felt heavier than you expected?", coverageTag: "emotion", kind: .default),
        QuestionTemplate(text: "What gave you a small sense of progress?", coverageTag: "action", kind: .default),
        QuestionTemplate(text: "What are you grateful for right now?", coverageTag: "gratitude", kind: .default),
        QuestionTemplate(text: "Who influenced your day the most?", coverageTag: "relationships", kind: .default),
        QuestionTemplate(text: "What did your body need today?", coverageTag: "health", kind: .default),
        QuestionTemplate(text: "What took most of your energy?", coverageTag: "work", kind: .default),
        QuestionTemplate(text: "What would you want to remember from today?", coverageTag: "values", kind: .default),
        QuestionTemplate(text: "What surprised you today?", coverageTag: "event", kind: .default),
        QuestionTemplate(text: "What did you avoid today?", coverageTag: "cause", kind: .default),
        QuestionTemplate(text: "What helped you feel grounded?", coverageTag: "emotion", kind: .default)
    ]

    func randomQuestion(
        avoidTopics: [String],
        excludingTags: Set<String> = []
    ) -> QuestionTemplate? {
        let filtered = filteredQuestions(avoidTopics: avoidTopics, excludingTags: excludingTags)
        return (filtered.isEmpty ? questions : filtered).randomElement()
    }

    func filteredQuestions(
        avoidTopics: [String],
        excludingTags: Set<String> = []
    ) -> [QuestionTemplate] {
        let loweredAvoid = avoidTopics.map { $0.lowercased() }.filter { !$0.isEmpty }
        return questions.filter { template in
            guard !excludingTags.contains(template.coverageTag) else { return false }
            if loweredAvoid.isEmpty { return true }
            let text = template.text.lowercased()
            return !loweredAvoid.contains(where: { text.contains($0) })
        }
    }
}
