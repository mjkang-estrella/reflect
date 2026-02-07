import Foundation
import Supabase

struct JournalRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) throws {
        if let client {
            self.client = client
        } else {
            self.client = try SupabaseClientProvider.makeClient()
        }
    }

    func fetchSessions(userId: UUID) async throws -> [JournalSessionRecord] {
        try await client
            .from("journal_sessions")
            .select()
            .eq("user_id", value: userId)
            .order("started_at", ascending: false)
            .execute()
            .value
    }

    func startVoiceSession(userId: UUID, startedAt: Date) async throws -> UUID {
        let sessionId = UUID()
        let newSession = NewJournalSession(
            id: sessionId,
            userId: userId,
            startedAt: startedAt,
            endedAt: nil,
            status: "draft",
            mode: "voice",
            title: nil,
            finalText: nil,
            durationSeconds: nil,
            tags: [],
            mood: nil,
            isFavorite: false,
            audioUrl: nil
        )

        try await client
            .from("journal_sessions")
            .insert(newSession)
            .execute()

        return sessionId
    }

    func startTextSession(userId: UUID, startedAt: Date) async throws -> UUID {
        let sessionId = UUID()
        let newSession = NewJournalSession(
            id: sessionId,
            userId: userId,
            startedAt: startedAt,
            endedAt: nil,
            status: "draft",
            mode: "text",
            title: nil,
            finalText: nil,
            durationSeconds: nil,
            tags: [],
            mood: nil,
            isFavorite: false,
            audioUrl: nil
        )

        try await client
            .from("journal_sessions")
            .insert(newSession)
            .execute()

        return sessionId
    }

    func completeVoiceSession(
        sessionId: UUID,
        transcript: String,
        durationSeconds: Int?,
        startedAt: Date,
        endedAt: Date
    ) async throws {
        let title = makeTitle()
        let update = UpdateJournalSession(
            endedAt: endedAt,
            status: "completed",
            title: title,
            finalText: transcript,
            durationSeconds: durationSeconds,
            audioUrl: nil
        )

        try await client
            .from("journal_sessions")
            .update(update)
            .eq("id", value: sessionId)
            .execute()

        let entry = NewJournalEntry(
            sessionId: sessionId,
            createdAt: startedAt,
            text: transcript,
            source: "user"
        )

        try await client
            .from("journal_entries")
            .insert(entry)
            .execute()

        let chunks = makeTranscriptChunks(
            sessionId: sessionId,
            transcript: transcript,
            baseTime: startedAt
        )

        if !chunks.isEmpty {
            try await client
                .from("transcript_chunks")
                .insert(chunks)
                .execute()
        }
    }

    func completeTextSession(
        sessionId: UUID,
        transcript: String,
        startedAt: Date,
        endedAt: Date
    ) async throws {
        let title = makeTitle()
        let update = UpdateJournalSession(
            endedAt: endedAt,
            status: "completed",
            title: title,
            finalText: transcript,
            durationSeconds: nil,
            audioUrl: nil
        )

        try await client
            .from("journal_sessions")
            .update(update)
            .eq("id", value: sessionId)
            .execute()

        let entry = NewJournalEntry(
            sessionId: sessionId,
            createdAt: startedAt,
            text: transcript,
            source: "user"
        )

        try await client
            .from("journal_entries")
            .insert(entry)
            .execute()

        let chunks = makeTranscriptChunks(
            sessionId: sessionId,
            transcript: transcript,
            baseTime: startedAt
        )

        if !chunks.isEmpty {
            try await client
                .from("transcript_chunks")
                .insert(chunks)
                .execute()
        }
    }

    func deleteSession(sessionId: UUID) async throws {
        try await client
            .from("journal_sessions")
            .delete()
            .eq("id", value: sessionId)
            .execute()
    }

    func insertSessionQuestion(_ question: NewSessionQuestion) async throws {
        try await client
            .from("session_questions")
            .insert(question)
            .execute()
    }

    func updateSessionQuestion(
        questionId: UUID,
        status: String,
        answeredText: String?
    ) async throws {
        let update = UpdateSessionQuestion(
            status: status,
            answeredText: answeredText
        )

        try await client
            .from("session_questions")
            .update(update)
            .eq("id", value: questionId)
            .execute()
    }

    func createVoiceSession(
        userId: UUID,
        transcript: String,
        durationSeconds: Int?,
        followUpPrompt: String?,
        startedAt: Date,
        endedAt: Date
    ) async throws {
        let sessionId = UUID()
        let title = makeTitle()
        let newSession = NewJournalSession(
            id: sessionId,
            userId: userId,
            startedAt: startedAt,
            endedAt: endedAt,
            status: "completed",
            mode: "voice",
            title: title,
            finalText: transcript,
            durationSeconds: durationSeconds,
            tags: [],
            mood: nil,
            isFavorite: false,
            audioUrl: nil
        )

        try await client
            .from("journal_sessions")
            .insert(newSession)
            .execute()

        let entry = NewJournalEntry(
            sessionId: sessionId,
            createdAt: startedAt,
            text: transcript,
            source: "user"
        )

        try await client
            .from("journal_entries")
            .insert(entry)
            .execute()

        if let followUpPrompt, !followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let question = NewSessionQuestion(
                id: UUID(),
                sessionId: sessionId,
                createdAt: startedAt,
                question: followUpPrompt,
                coverageTag: "follow_up",
                status: "shown",
                answeredText: nil
            )

            try await client
                .from("session_questions")
                .insert(question)
                .execute()
        }

        let chunks = makeTranscriptChunks(
            sessionId: sessionId,
            transcript: transcript,
            baseTime: startedAt
        )

        if !chunks.isEmpty {
            try await client
                .from("transcript_chunks")
            .insert(chunks)
            .execute()
        }
    }

    func updateAudioURL(sessionId: UUID, audioUrl: String) async throws {
        let update = UpdateJournalSessionAudio(audioUrl: audioUrl)

        try await client
            .from("journal_sessions")
            .update(update)
            .eq("id", value: sessionId)
            .execute()
    }

    func updateTitle(sessionId: UUID, title: String) async throws {
        let update = UpdateJournalSessionTitle(title: title)

        try await client
            .from("journal_sessions")
            .update(update)
            .eq("id", value: sessionId)
            .execute()
    }

    func fetchSummary(sessionId: UUID) async throws -> SummaryPayload? {
        let records: [DailySummaryRecord] = try await client
            .from("daily_summaries")
            .select()
            .eq("session_id", value: sessionId)
            .limit(1)
            .execute()
            .value

        return records.first?.summaryJson
    }

    func fetchSummaries(sessionIds: [UUID]) async throws -> [UUID: SummaryPayload] {
        guard !sessionIds.isEmpty else { return [:] }
        let ids = sessionIds.map { $0.uuidString }.joined(separator: ",")
        let records: [DailySummaryRecord] = try await client
            .from("daily_summaries")
            .select()
            .filter("session_id", operator: "in", value: "(\(ids))")
            .execute()
            .value

        return Dictionary(uniqueKeysWithValues: records.map { ($0.sessionId, $0.summaryJson) })
    }

    private func makeTitle() -> String? {
        return nil
    }

    private func makeTranscriptChunks(
        sessionId: UUID,
        transcript: String,
        baseTime: Date
    ) -> [NewTranscriptChunk] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let chunks = lines.isEmpty ? [trimmed] : lines

        return chunks.enumerated().map { index, text in
            NewTranscriptChunk(
                sessionId: sessionId,
                createdAt: baseTime.addingTimeInterval(Double(index) * 0.25),
                text: text,
                confidence: nil,
                provider: "on_device"
            )
        }
    }
}

private struct UpdateJournalSession: Encodable {
    let endedAt: Date
    let status: String
    let title: String?
    let finalText: String
    let durationSeconds: Int?
    let audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case endedAt = "ended_at"
        case status
        case title
        case finalText = "final_text"
        case durationSeconds = "duration_seconds"
        case audioUrl = "audio_url"
    }
}

private struct UpdateJournalSessionAudio: Encodable {
    let audioUrl: String

    enum CodingKeys: String, CodingKey {
        case audioUrl = "audio_url"
    }
}

private struct UpdateJournalSessionTitle: Encodable {
    let title: String
}

private struct UpdateSessionQuestion: Encodable {
    let status: String
    let answeredText: String?

    enum CodingKeys: String, CodingKey {
        case status
        case answeredText = "answered_text"
    }
}
