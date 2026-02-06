import Foundation
import Supabase

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
}

private struct MeDbProfileRecord: Codable {
    let userId: UUID
    let profile: ProfileSettings?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profile = "profile_json"
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
