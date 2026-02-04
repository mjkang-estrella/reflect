import Combine
import Foundation
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var configurationError: String?
    @Published private(set) var isReady = false

    private let client: SupabaseClient?
    private var authTask: Task<Void, Never>?

    init() {
        do {
            client = try SupabaseClientProvider.makeClient()
        } catch {
            configurationError = error.localizedDescription
            client = nil
        }

        session = client?.auth.currentSession

        authTask = Task { [weak self] in
            await self?.observeAuthChanges()
        }
    }

    deinit {
        authTask?.cancel()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var userId: String? {
        session?.user.id.uuidString
    }

    var userEmail: String? {
        session?.user.email
    }

    func signInWithApple() async throws {
        guard let client else {
            throw AuthStoreError.notConfigured
        }

        guard let redirectURL else {
            throw AuthStoreError.missingRedirectURL
        }

        session = try await client.auth.signInWithOAuth(
            provider: .apple,
            redirectTo: redirectURL
        )
    }

    func signIn(email: String, password: String) async throws {
        guard let client else {
            throw AuthStoreError.notConfigured
        }

        session = try await client.auth.signIn(
            email: email,
            password: password
        )
    }

    func signUp(email: String, password: String) async throws -> AuthResponse {
        guard let client else {
            throw AuthStoreError.notConfigured
        }

        let response = try await client.auth.signUp(
            email: email,
            password: password
        )

        if case let .session(newSession) = response {
            session = newSession
        }

        return response
    }

    func signOut() async throws {
        guard let client else {
            throw AuthStoreError.notConfigured
        }

        try await client.auth.signOut()
        session = nil
    }

    private func observeAuthChanges() async {
        guard let client else {
            isReady = true
            return
        }

        isReady = true

        for await (_, session) in client.auth.authStateChanges {
            self.session = session
        }
    }

    func handleOpenURL(_ url: URL) {
        guard let client else { return }
        client.handle(url)
    }

    private var redirectURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_REDIRECT_URL") as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return URL(string: trimmed)
    }
}

enum AuthStoreError: LocalizedError {
    case notConfigured
    case missingRedirectURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured."
        case .missingRedirectURL:
            return "Missing SUPABASE_REDIRECT_URL in Info.plist."
        }
    }
}
