import Foundation
import Testing
@testable import reflect

struct QuestionEngineTests {
    @Test func sentenceBoundaryRequiredForValidation() {
        let engine = QuestionEngine()
        let question = QuestionItem(
            id: UUID(),
            text: "What made you feel calm?",
            coverageTag: "emotion",
            kind: .followUp,
            status: .shown,
            askedAt: Date()
        )
        engine.setCurrentQuestion(question, wordCount: 0, now: Date())

        let actionWithoutBoundary = engine.evaluateTranscript(
            fullText: "I felt calm because I took a walk",
            committedLines: ["I felt calm because I took a walk"],
            currentLine: "",
            now: Date(),
            proactivity: .medium
        )
        #expect(actionWithoutBoundary == nil)

        let actionWithBoundary = engine.evaluateTranscript(
            fullText: "I felt calm because I took a walk.",
            committedLines: ["I felt calm because I took a walk."],
            currentLine: "",
            now: Date(),
            proactivity: .medium
        )
        #expect(actionWithBoundary == .validateAnswer(recentText: "I felt calm because I took a walk."))
    }

    @Test func preferredKindAfterAnsweredIsFollowUp() {
        let engine = QuestionEngine()
        let question = QuestionItem(
            id: UUID(),
            text: "What was the highlight?",
            coverageTag: "event",
            kind: .default,
            status: .answered,
            askedAt: Date()
        )
        engine.setCurrentQuestion(question, wordCount: 5, now: Date())
        engine.updateCurrentQuestionStatus(.answered)

        let kind = engine.preferredNextKind(reason: .answered)
        #expect(kind == .followUp)
    }

    @Test func followUpLimitForcesNewTopic() {
        let engine = QuestionEngine()
        let first = QuestionItem(
            id: UUID(),
            text: "What did you learn?",
            coverageTag: "values",
            kind: .followUp,
            status: .shown,
            askedAt: Date()
        )
        let second = QuestionItem(
            id: UUID(),
            text: "How did that change you?",
            coverageTag: "values",
            kind: .followUp,
            status: .shown,
            askedAt: Date()
        )
        engine.setCurrentQuestion(first, wordCount: 5, now: Date())
        engine.setCurrentQuestion(second, wordCount: 10, now: Date())
        engine.updateCurrentQuestionStatus(.answered)

        let kind = engine.preferredNextKind(reason: .answered)
        #expect(kind == .newTopic)
    }

    @Test func refreshForcesNewTopic() {
        let engine = QuestionEngine()
        let kind = engine.preferredNextKind(reason: .refresh)
        #expect(kind == .newTopic)
    }

    @Test func avoidTopicsFilterRemovesBlockedText() {
        let pool = QuestionPool.shared
        let filtered = pool.filteredQuestions(avoidTopics: ["body"])
        let containsBlocked = filtered.contains { template in
            template.text.lowercased().contains("body")
        }
        #expect(containsBlocked == false)
    }
}
