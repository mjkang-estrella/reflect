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

    func createVoiceSession(
        userId: UUID,
        transcript: String,
        durationSeconds: Int?,
        followUpPrompt: String?,
        startedAt: Date,
        endedAt: Date
    ) async throws {
        let sessionId = UUID()
        let title = makeTitle(from: transcript)
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
            isFavorite: false
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
                sessionId: sessionId,
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

    private func makeTitle(from transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let firstLine = trimmed.split(whereSeparator: \.isNewline).first {
            let raw = String(firstLine)
            let capped = raw.prefix(72)
            return String(capped)
        }

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
