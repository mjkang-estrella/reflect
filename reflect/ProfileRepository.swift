import Foundation
import Supabase

struct MeDbDebugSnapshot {
    let userId: UUID
    let updatedAt: String
    let profileJSON: String
    let stateJSON: String
    let patternsJSON: String
    let trustJSON: String
}

struct ProfileRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) throws {
        if let client {
            self.client = client
        } else {
            self.client = try SupabaseClientProvider.makeClient()
        }
    }

    func fetchProfile(userId: UUID) async throws -> ProfileSettings? {
        let records: [MeDbProfileRecord] = try await client
            .from("me_db")
            .select("user_id, profile_json")
            .eq("user_id", value: userId)
            .execute()
            .value

        return records.first?.profile
    }

    func saveProfile(userId: UUID, profile: ProfileSettings) async throws {
        let payload = NewMeDbProfile(
            userId: userId,
            profile: profile,
            updatedAt: Date()
        )

        try await client
            .from("me_db")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }

    func fetchMeDbDebugSnapshot(userId: UUID) async throws -> MeDbDebugSnapshot? {
        let records: [MeDbDebugRecord] = try await client
            .from("me_db")
            .select(
                """
                user_id,
                profile_json_text:profile_json::text,
                state_json_text:state_json::text,
                patterns_json_text:patterns_json::text,
                trust_json_text:trust_json::text,
                updated_at_text:updated_at::text
                """
            )
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let record = records.first else { return nil }

        return MeDbDebugSnapshot(
            userId: record.userId,
            updatedAt: record.updatedAtText,
            profileJSON: prettyJSONString(from: record.profileJsonText),
            stateJSON: prettyJSONString(from: record.stateJsonText),
            patternsJSON: prettyJSONString(from: record.patternsJsonText),
            trustJSON: prettyJSONString(from: record.trustJsonText)
        )
    }

    private func prettyJSONString(from raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return raw
        }

        return pretty
    }
}

private struct MeDbProfileRecord: Codable {
    let userId: UUID
    let profile: ProfileSettings?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profile = "profile_json"
    }
}

private struct MeDbDebugRecord: Codable {
    let userId: UUID
    let profileJsonText: String
    let stateJsonText: String
    let patternsJsonText: String
    let trustJsonText: String
    let updatedAtText: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profileJsonText = "profile_json_text"
        case stateJsonText = "state_json_text"
        case patternsJsonText = "patterns_json_text"
        case trustJsonText = "trust_json_text"
        case updatedAtText = "updated_at_text"
    }
}

private struct NewMeDbProfile: Encodable {
    let userId: UUID
    let profile: ProfileSettings
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profile = "profile_json"
        case updatedAt = "updated_at"
    }
}
