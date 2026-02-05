import Foundation

enum QuestionTriggerReason: String, Codable {
    case answered
    case refresh
    case interval
    case silence
}

enum QuestionEngineAction: Equatable {
    case validateAnswer(recentText: String)
    case requestNextQuestion(reason: QuestionTriggerReason, recentText: String)
}

final class QuestionEngine {
    private let minimumWordsForAnswer = 6
    private let silenceThreshold: TimeInterval = 4.5
    private let answerMarkers = [
        "because",
        "so",
        "it felt",
        "i felt",
        "i realized",
        "i think",
        "i noticed",
        "i wanted",
        "i decided"
    ]

    private let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "this", "that", "these", "those",
        "i", "you", "we", "they", "he", "she", "it", "me", "my", "your", "our", "their",
        "to", "for", "of", "in", "on", "at", "with", "from", "by", "about", "as", "is", "are",
        "was", "were", "be", "been", "being", "do", "did", "does", "have", "has", "had",
        "what", "why", "how", "when", "where", "which", "who", "whom"
    ]

    private(set) var currentQuestion: QuestionItem?
    private(set) var questionHistory: [QuestionItem] = []

    private var lastQuestionAskedAt: Date?
    private var lastTranscriptUpdateAt: Date?
    private var lastSilenceTriggerAt: Date?
    private var lastProcessedSentence: String?
    private var wordCountAtQuestion = 0

    func reset() {
        currentQuestion = nil
        questionHistory = []
        lastQuestionAskedAt = nil
        lastTranscriptUpdateAt = nil
        lastSilenceTriggerAt = nil
        lastProcessedSentence = nil
        wordCountAtQuestion = 0
    }

    func setCurrentQuestion(_ question: QuestionItem, wordCount: Int, now: Date) {
        currentQuestion = question
        wordCountAtQuestion = wordCount
        lastQuestionAskedAt = now
        lastProcessedSentence = nil

        if let index = questionHistory.firstIndex(where: { $0.id == question.id }) {
            questionHistory[index] = question
        } else {
            questionHistory.append(question)
        }
    }

    func updateCurrentQuestionStatus(_ status: QuestionStatus) {
        guard var question = currentQuestion else { return }
        question.status = status
        currentQuestion = question
        if let index = questionHistory.firstIndex(where: { $0.id == question.id }) {
            questionHistory[index] = question
        }
    }

    func markTranscriptUpdate(now: Date) {
        lastTranscriptUpdateAt = now
    }

    func evaluateTranscript(
        fullText: String,
        committedLines: [String],
        currentLine: String,
        now: Date,
        proactivity: Proactivity
    ) -> QuestionEngineAction? {
        markTranscriptUpdate(now: now)

        guard let question = currentQuestion else { return nil }
        if question.status == .pendingValidation || question.status == .answered || question.status == .ignored {
            return nil
        }

        let recentText = buildRecentText(committedLines: committedLines, currentLine: currentLine)
        let latestLine = latestLineText(committedLines: committedLines, currentLine: currentLine)
        let sentenceBoundary = isSentenceBoundary(latestLine)

        if question.status == .shown,
           sentenceBoundary,
           shouldValidateAnswer(for: question, recentText: recentText, fullText: fullText),
           shouldProcessSentence(latestLine) {
            lastProcessedSentence = latestLine.lowercased()
            return .validateAnswer(recentText: recentText)
        }

        if sentenceBoundary,
           shouldRequestNextQuestion(now: now, proactivity: proactivity) {
            return .requestNextQuestion(reason: .interval, recentText: recentText)
        }

        return nil
    }

    func evaluateSilence(
        fullText: String,
        committedLines: [String],
        currentLine: String,
        now: Date,
        proactivity: Proactivity
    ) -> QuestionEngineAction? {
        guard let lastUpdate = lastTranscriptUpdateAt else { return nil }
        guard now.timeIntervalSince(lastUpdate) >= silenceThreshold else { return nil }
        if let lastSilenceTriggerAt, lastUpdate <= lastSilenceTriggerAt { return nil }
        guard shouldRequestNextQuestion(now: now, proactivity: proactivity) else { return nil }

        lastSilenceTriggerAt = now
        let recentText = buildRecentText(committedLines: committedLines, currentLine: currentLine)
        return .requestNextQuestion(reason: .silence, recentText: recentText)
    }

    func preferredNextKind(reason: QuestionTriggerReason) -> QuestionKind {
        if reason == .refresh { return .newTopic }
        if let currentQuestion, currentQuestion.status == .answered {
            let consecutiveFollowUps = countConsecutiveFollowUps()
            if consecutiveFollowUps >= 2 {
                return .newTopic
            }
            return .followUp
        }

        let lastTwo = questionHistory.suffix(2)
        if lastTwo.count == 2 {
            let kinds = lastTwo.map { $0.kind }
            if kinds[0] == kinds[1] { return .newTopic }
        }

        return .default
    }

    func minInterval(for proactivity: Proactivity) -> TimeInterval {
        switch proactivity {
        case .low:
            return 45
        case .medium:
            return 30
        case .high:
            return 20
        }
    }

    func buildRecentText(committedLines: [String], currentLine: String) -> String {
        var lines = committedLines
        if !currentLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(currentLine)
        }
        let recent = lines.suffix(3)
        return recent.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldValidateAnswer(for question: QuestionItem, recentText: String, fullText: String) -> Bool {
        let totalWords = wordCount(for: fullText)
        let newWords = max(0, totalWords - wordCountAtQuestion)
        guard newWords >= minimumWordsForAnswer else { return false }

        let loweredRecent = recentText.lowercased()
        if answerMarkers.contains(where: { loweredRecent.contains($0) }) {
            return true
        }

        let keywords = extractKeywords(from: question.text)
        if keywords.isEmpty { return false }
        return keywords.contains(where: { loweredRecent.contains($0) })
    }

    private func shouldRequestNextQuestion(now: Date, proactivity: Proactivity) -> Bool {
        if let status = currentQuestion?.status, status == .pendingValidation || status == .answered || status == .ignored {
            return false
        }
        let interval = minInterval(for: proactivity)
        guard let lastAskedAt = lastQuestionAskedAt else { return true }
        return now.timeIntervalSince(lastAskedAt) >= interval
    }

    private func latestLineText(committedLines: [String], currentLine: String) -> String {
        let trimmedCurrent = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty {
            return trimmedCurrent
        }
        return committedLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func isSentenceBoundary(_ line: String) -> Bool {
        guard let lastChar = line.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return lastChar == "." || lastChar == "?" || lastChar == "!"
    }

    private func shouldProcessSentence(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if let lastProcessedSentence {
            return lastProcessedSentence != normalized
        }
        return true
    }

    private func extractKeywords(from question: String) -> [String] {
        let lowered = question.lowercased()
        let tokens = lowered.split { !$0.isLetter }
        return tokens
            .map(String.init)
            .filter { $0.count > 2 }
            .filter { !stopwords.contains($0) }
    }

    private func wordCount(for text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private func countConsecutiveFollowUps() -> Int {
        var count = 0
        for question in questionHistory.reversed() {
            if question.kind == .followUp {
                count += 1
            } else {
                break
            }
        }
        return count
    }
}
