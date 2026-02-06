import Foundation

enum TranscriptionBackend: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case mistral = "mistral"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .mistral:
            return "Mistral"
        }
    }

    var functionName: String {
        switch self {
        case .openAI:
            return "transcribe"
        case .mistral:
            return "transcribe-mistral"
        }
    }
}

enum TranscriptionRuntimeSettings {
    static let backendKey = "transcriptionBackend"
    static let defaultBackend: TranscriptionBackend = .openAI

    static func selectedBackend(from defaults: UserDefaults = .standard) -> TranscriptionBackend {
        guard
            let rawValue = defaults.string(forKey: backendKey),
            let backend = TranscriptionBackend(rawValue: rawValue)
        else {
            return defaultBackend
        }

        return backend
    }
}
