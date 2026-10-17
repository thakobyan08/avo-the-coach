import Foundation

nonisolated struct WorkHours: Equatable, Sendable {
    /// Calendar weekdays, 1 = Sunday.
    var days: Set<Int>
    /// Minutes after midnight.
    var startMinute: Int
    /// Minutes after midnight. Earlier than `startMinute` means the hours run past midnight.
    var endMinute: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let now = hour * 60 + minute

        if startMinute < endMinute {
            return days.contains(weekday) && now >= startMinute && now < endMinute
        }
        if startMinute == endMinute {
            return days.contains(weekday)
        }
        // Overnight: the hours after midnight belong to the day they started on.
        if now >= startMinute { return days.contains(weekday) }
        if now < endMinute { return days.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }
}
