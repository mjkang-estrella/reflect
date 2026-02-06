import Testing
@testable import reflect

struct TimeFormatterTests {
    @Test func formatsMinutesAndSeconds() async throws {
        #expect(TimeFormatter.mmss(0) == "0:00")
        #expect(TimeFormatter.mmss(65) == "1:05")
        #expect(TimeFormatter.mmss(125) == "2:05")
    }
}
