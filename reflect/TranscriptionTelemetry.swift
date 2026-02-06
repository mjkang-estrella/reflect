import Foundation
import os

enum TranscriptionTelemetry {
    private static let logger = Logger(subsystem: "com.mjkang.reflect", category: "transcription")

    static func track(_ name: String, fields: [String: String] = [:]) {
        #if DEBUG
            let payload = fields
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            if payload.isEmpty {
                logger.log("event=\(name, privacy: .public)")
            } else {
                logger.log("event=\(name, privacy: .public) \(payload, privacy: .public)")
            }
        #endif
    }
}
