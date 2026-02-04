import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var isWorking = false
    @State private var alertItem: LoginAlert?
    @State private var email = ""
    @State private var password = ""
    @State private var emailMode: EmailAuthMode = .signIn

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.2),
                        Color(red: 0.18, green: 0.19, blue: 0.32),
                        Color(red: 0.87, green: 0.66, blue: 0.58),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Reflect")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundColor(.white)

                        Text("Continue with Apple to begin your daily practice.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button(action: signInWithApple) {
                            HStack(spacing: 10) {
                                Image(systemName: "applelogo")
                                    .font(.system(size: 18, weight: .semibold))

                                Text("Continue with Apple")
                                    .font(.system(size: 16, weight: .semibold))

                                if isWorking {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .disabled(isWorking)

                        Text("More sign-in options are coming soon.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        Text("Log in with email")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))

                        Picker("Email Mode", selection: $emailMode) {
                            ForEach(EmailAuthMode.allCases) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 10) {
                            TextField("Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .padding(12)
                                .background(Color.white.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .padding(12)
                                .background(Color.white.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button(action: signInWithEmail) {
                            HStack(spacing: 8) {
                                Text(emailMode.buttonTitle)
                                    .font(.system(size: 16, weight: .semibold))

                                if isWorking {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(Color(red: 0.08, green: 0.1, blue: 0.18))
                            .clipShape(Capsule())
                        }
                        .disabled(isWorking || !canSubmitEmail)

                        if emailMode == .signUp {
                            Text("We’ll email you if confirmation is required.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(item: $alertItem) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func signInWithApple() {
        guard !isWorking else { return }

        Task {
            isWorking = true
            defer { isWorking = false }

            do {
                try await authStore.signInWithApple()
            } catch {
                alertItem = LoginAlert(
                    title: "Authentication failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func signInWithEmail() {
        guard !isWorking, canSubmitEmail else { return }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            isWorking = true
            defer { isWorking = false }

            do {
                switch emailMode {
                case .signIn:
                    try await authStore.signIn(email: trimmedEmail, password: trimmedPassword)
                case .signUp:
                    _ = try await authStore.signUp(email: trimmedEmail, password: trimmedPassword)
                    if authStore.session == nil {
                        alertItem = LoginAlert(
                            title: "Check your email",
                            message: "Confirm your email address to finish signing up."
                        )
                    }
                }
            } catch {
                alertItem = LoginAlert(
                    title: "Authentication failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private var canSubmitEmail: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum EmailAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn:
            return "Sign In"
        case .signUp:
            return "Create Account"
        }
    }

    var buttonTitle: String {
        switch self {
        case .signIn:
            return "Continue with Email"
        case .signUp:
            return "Create Account"
        }
    }
}

private struct LoginAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}
