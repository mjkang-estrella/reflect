import Foundation
import Testing
@testable import reflect

struct TranscriptionRuntimeSettingsTests {
    @Test func defaultsWhenUnset() {
        let defaults = UserDefaults(suiteName: "TranscriptionRuntimeSettingsTests.defaults")!
        defaults.removePersistentDomain(forName: "TranscriptionRuntimeSettingsTests.defaults")

        let backend = TranscriptionRuntimeSettings.selectedBackend(from: defaults)
        let streamingEnabled = TranscriptionRuntimeSettings.isStreamingEnabled(from: defaults)

        #expect(backend == .openAI)
        #expect(streamingEnabled == false)
    }

    @Test func resolvesStoredValues() {
        let suiteName = "TranscriptionRuntimeSettingsTests.stored"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(TranscriptionBackend.mistral.rawValue, forKey: TranscriptionRuntimeSettings.backendKey)
        defaults.set(true, forKey: TranscriptionRuntimeSettings.streamingEnabledKey)

        let backend = TranscriptionRuntimeSettings.selectedBackend(from: defaults)
        let streamingEnabled = TranscriptionRuntimeSettings.isStreamingEnabled(from: defaults)

        #expect(backend == .mistral)
        #expect(streamingEnabled == true)
    }
}
