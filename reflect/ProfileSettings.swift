import Foundation

struct ProfileSettings: Codable, Equatable {
    var schemaVersion: Int
    var name: String
    var displayName: String
    var pronouns: String
    var timezone: String
    var tone: Tone
    var proactivity: Proactivity
    var avoidTopics: String
    var notes: String
    var lastUpdatedBy: String
    var lastUpdatedAt: String

    init(
        displayName: String,
        tone: Tone,
        proactivity: Proactivity,
        avoidTopics: String,
        schemaVersion: Int = 1,
        name: String = "",
        pronouns: String = "",
        timezone: String = TimeZone.current.identifier,
        notes: String = "",
        lastUpdatedBy: String = "user",
        lastUpdatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.displayName = displayName
        self.pronouns = pronouns
        self.timezone = timezone
        self.tone = tone
        self.proactivity = proactivity
        self.avoidTopics = avoidTopics
        self.notes = notes
        self.lastUpdatedBy = lastUpdatedBy
        self.lastUpdatedAt = lastUpdatedAt
    }

    static let empty = ProfileSettings(
        displayName: "",
        tone: .balanced,
        proactivity: .medium,
        avoidTopics: ""
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case displayName
        case pronouns
        case timezone
        case tone
        case proactivity
        case avoidTopics
        case notes
        case lastUpdatedBy
        case lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        pronouns = try container.decodeIfPresent(String.self, forKey: .pronouns) ?? ""
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? TimeZone.current.identifier
        tone = try container.decodeIfPresent(Tone.self, forKey: .tone) ?? .balanced
        proactivity = try container.decodeIfPresent(Proactivity.self, forKey: .proactivity) ?? .medium
        avoidTopics = try container.decodeIfPresent(String.self, forKey: .avoidTopics) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        lastUpdatedBy = try container.decodeIfPresent(String.self, forKey: .lastUpdatedBy) ?? "user"
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(pronouns, forKey: .pronouns)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(tone, forKey: .tone)
        try container.encode(proactivity, forKey: .proactivity)
        try container.encode(avoidTopics, forKey: .avoidTopics)
        try container.encode(notes, forKey: .notes)
        try container.encode(lastUpdatedBy, forKey: .lastUpdatedBy)
        try container.encode(lastUpdatedAt, forKey: .lastUpdatedAt)
    }
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
