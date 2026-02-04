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
        let existing: [MeDbProfileIdRecord] = try await client
            .from("me_db")
            .select("user_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        let now = Date()

        if existing.isEmpty {
            let newProfile = NewMeDbProfile(
                userId: userId,
                profile: profile,
                updatedAt: now
            )

            try await client
                .from("me_db")
                .insert(newProfile)
                .execute()
        } else {
            let update = UpdateMeDbProfile(
                profile: profile,
                updatedAt: now
            )

            try await client
                .from("me_db")
                .update(update)
                .eq("user_id", value: userId)
                .execute()
        }
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

private struct MeDbProfileIdRecord: Codable {
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
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

private struct UpdateMeDbProfile: Encodable {
    let profile: ProfileSettings
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case profile = "profile_json"
        case updatedAt = "updated_at"
    }
}
