import Foundation
import Supabase

struct AudioStorageService {
    static let bucketName = "journal-audio"

    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) throws {
        if let client {
            self.client = client
        } else {
            self.client = try SupabaseClientProvider.makeClient()
        }
    }

    func uploadAudio(fileURL: URL, userId: UUID, sessionId: UUID) async throws -> String {
        let path = "\(userId.uuidString)/\(sessionId.uuidString).wav"
        let response = try await client.storage
            .from(Self.bucketName)
            .upload(
                path,
                fileURL: fileURL,
                options: FileOptions(contentType: "audio/wav", upsert: true)
            )
        return response.path
    }

    func signedURL(for pathOrUrl: String, expiresIn: Int = 3600) async throws -> URL {
        if let url = URL(string: pathOrUrl), let scheme = url.scheme, scheme.hasPrefix("http") {
            return url
        }

        let cleanedPath = normalizedPath(from: pathOrUrl)

        let signed = try await client.storage
            .from(Self.bucketName)
            .createSignedURL(path: cleanedPath, expiresIn: expiresIn)
        return signed
    }

    func deleteAudio(pathOrUrl: String) async throws {
        let cleanedPath = normalizedPath(from: pathOrUrl)
        try await client.storage
            .from(Self.bucketName)
            .remove(paths: [cleanedPath])
    }

    private func normalizedPath(from pathOrUrl: String) -> String {
        if let url = URL(string: pathOrUrl), let scheme = url.scheme, scheme.hasPrefix("http") {
            let path = url.path
            if let range = path.range(of: "/\(Self.bucketName)/") {
                return String(path[range.upperBound...])
            }
            return url.lastPathComponent
        }

        if pathOrUrl.hasPrefix("\(Self.bucketName)/") {
            return String(pathOrUrl.dropFirst(Self.bucketName.count + 1))
        }

        return pathOrUrl
    }
}
