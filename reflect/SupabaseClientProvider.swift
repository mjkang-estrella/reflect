import Foundation
import Supabase

enum SupabaseClientProvider {
    static func makeClient() throws -> SupabaseClient {
        let urlString = try loadValue(forKey: "SUPABASE_URL", error: .missingURL)
        let anonKey = try loadValue(forKey: "SUPABASE_ANON_KEY", error: .missingAnonKey)

        guard let url = URL(string: urlString) else {
            throw SupabaseConfigurationError.invalidURL(urlString)
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey
        )
    }

    private static func loadValue(forKey key: String, error: SupabaseConfigurationError) throws -> String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            throw error
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.uppercased().contains("YOUR_") {
            throw error
        }

        return value
    }
}

enum SupabaseConfigurationError: LocalizedError {
    case missingURL
    case missingAnonKey
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Missing SUPABASE_URL in Info.plist."
        case .missingAnonKey:
            return "Missing SUPABASE_ANON_KEY in Info.plist."
        case .invalidURL(let url):
            return "SUPABASE_URL is invalid: \(url)"
        }
    }
}
