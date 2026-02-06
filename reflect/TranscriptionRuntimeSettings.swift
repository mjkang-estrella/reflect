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
    static let streamingEnabledKey = "transcriptionStreamingEnabled"
    static let defaultBackend: TranscriptionBackend = .openAI
    static let defaultStreamingEnabled = false

    static func selectedBackend(from defaults: UserDefaults = .standard) -> TranscriptionBackend {
        guard
            let rawValue = defaults.string(forKey: backendKey),
            let backend = TranscriptionBackend(rawValue: rawValue)
        else {
            return defaultBackend
        }

        return backend
    }

    static func isStreamingEnabled(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: streamingEnabledKey) == nil {
            return defaultStreamingEnabled
        }

        return defaults.bool(forKey: streamingEnabledKey)
    }
}
