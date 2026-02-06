import Foundation
import Testing
@testable import reflect

struct JournalReminderConfigurationTests {
    @Test func normalizesHourAndMinuteFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 6
        components.hour = 21
        components.minute = 45
        let date = calendar.date(from: components) ?? Date()

        let normalized = JournalReminderConfiguration.normalizedHourMinute(from: date, calendar: calendar)
        #expect(normalized.hour == 21)
        #expect(normalized.minute == 45)
    }

    @Test func buildsReminderDateWithProvidedTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        var nowComponents = DateComponents()
        nowComponents.year = 2026
        nowComponents.month = 2
        nowComponents.day = 6
        nowComponents.hour = 8
        nowComponents.minute = 0
        let now = calendar.date(from: nowComponents) ?? Date()

        let reminderDate = JournalReminderConfiguration.reminderDate(
            hour: 19,
            minute: 30,
            now: now,
            calendar: calendar
        )
        let reminderComponents = calendar.dateComponents([.hour, .minute], from: reminderDate)

        #expect(reminderComponents.hour == 19)
        #expect(reminderComponents.minute == 30)
    }
}
