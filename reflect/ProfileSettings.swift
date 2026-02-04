import Foundation

struct ProfileSettings: Codable, Equatable {
    var displayName: String
    var tone: Tone
    var proactivity: Proactivity
    var avoidTopics: String

    static let empty = ProfileSettings(
        displayName: "",
        tone: .balanced,
        proactivity: .medium,
        avoidTopics: ""
    )
}

enum Tone: String, CaseIterable, Identifiable, Codable {
    case gentle
    case balanced
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle:
            return "Gentle"
        case .balanced:
            return "Balanced"
        case .direct:
            return "Direct"
        }
    }
}

enum Proactivity: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}
