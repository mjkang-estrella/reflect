import Foundation
import UserNotifications

enum JournalReminderConfiguration {
    static let enabledKey = "journalReminderEnabled"
    static let hourKey = "journalReminderHour"
    static let minuteKey = "journalReminderMinute"
    static let requestIdentifier = "daily-journal-reminder"
    static let defaultHour = 20
    static let defaultMinute = 0

    static func normalizedHourMinute(
        from date: Date,
        calendar: Calendar = .current
    ) -> (hour: Int, minute: Int) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? defaultHour
        let minute = components.minute ?? defaultMinute
        return (hour, minute)
    }

    static func reminderDate(
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? now
    }
}

@MainActor
final class JournalReminderManager {
    static let shared = JournalReminderManager()

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
    }

    func configureOnLaunch() {
        Task {
            await syncScheduledReminderWithStoredPreferences()
        }
    }

    func setReminderEnabled(_ isEnabled: Bool, at date: Date) async -> Bool {
        guard isEnabled else {
            defaults.set(false, forKey: JournalReminderConfiguration.enabledKey)
            center.removePendingNotificationRequests(withIdentifiers: [JournalReminderConfiguration.requestIdentifier])
            return true
        }

        let permissionGranted = await requestAuthorizationIfNeeded()
        guard permissionGranted else {
            defaults.set(false, forKey: JournalReminderConfiguration.enabledKey)
            center.removePendingNotificationRequests(withIdentifiers: [JournalReminderConfiguration.requestIdentifier])
            return false
        }

        defaults.set(true, forKey: JournalReminderConfiguration.enabledKey)
        saveReminderTime(date)
        await scheduleDailyReminder(at: date)
        return true
    }

    func setReminderTime(_ date: Date) async {
        saveReminderTime(date)
        guard defaults.bool(forKey: JournalReminderConfiguration.enabledKey) else { return }
        await scheduleDailyReminder(at: date)
    }

    func syncScheduledReminderWithStoredPreferences() async {
        guard defaults.bool(forKey: JournalReminderConfiguration.enabledKey) else {
            center.removePendingNotificationRequests(withIdentifiers: [JournalReminderConfiguration.requestIdentifier])
            return
        }

        let reminderDate = storedReminderDate()
        let permissionGranted = await requestAuthorizationIfNeeded()

        guard permissionGranted else {
            defaults.set(false, forKey: JournalReminderConfiguration.enabledKey)
            center.removePendingNotificationRequests(withIdentifiers: [JournalReminderConfiguration.requestIdentifier])
            return
        }

        await scheduleDailyReminder(at: reminderDate)
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func scheduleDailyReminder(at date: Date) async {
        let normalizedTime = JournalReminderConfiguration.normalizedHourMinute(from: date, calendar: calendar)
        var triggerComponents = DateComponents()
        triggerComponents.hour = normalizedTime.hour
        triggerComponents.minute = normalizedTime.minute

        let content = UNMutableNotificationContent()
        content.title = "Time to journal"
        content.body = "Take a moment to reflect on your day."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: JournalReminderConfiguration.requestIdentifier,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [JournalReminderConfiguration.requestIdentifier])
        do {
            try await center.add(request)
        } catch {
            defaults.set(false, forKey: JournalReminderConfiguration.enabledKey)
        }
    }

    private func saveReminderTime(_ date: Date) {
        let normalizedTime = JournalReminderConfiguration.normalizedHourMinute(from: date, calendar: calendar)
        defaults.set(normalizedTime.hour, forKey: JournalReminderConfiguration.hourKey)
        defaults.set(normalizedTime.minute, forKey: JournalReminderConfiguration.minuteKey)
    }

    private func storedReminderDate() -> Date {
        let hourObject = defaults.object(forKey: JournalReminderConfiguration.hourKey)
        let minuteObject = defaults.object(forKey: JournalReminderConfiguration.minuteKey)
        let hour = (hourObject as? Int) ?? JournalReminderConfiguration.defaultHour
        let minute = (minuteObject as? Int) ?? JournalReminderConfiguration.defaultMinute

        return JournalReminderConfiguration.reminderDate(
            hour: hour,
            minute: minute,
            calendar: calendar
        )
    }
}
