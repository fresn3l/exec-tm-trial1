import Foundation

/// The instant a plan day starts. Hours before `hour` still belong to the previous plan day.
public struct DayBoundary: Hashable, Sendable {
    public let hour: Int
    public let calendar: Calendar

    public init(hour: Int, timeZone: TimeZone) {
        self.hour = min(23, max(0, hour))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public init(settings: PlannerSettings, timeZone: TimeZone) {
        self.init(hour: settings.dayBoundaryHour, timeZone: timeZone)
    }

    /// `hour:00:00` belongs to the plan day of that civil date.
    /// One minute earlier belongs to the previous plan day.
    public func planDay(containing date: Date) -> PlanDay {
        let hourNow = calendar.component(.hour, from: date)
        let anchor = hourNow < hour
            ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date)
            : date
        let parts = calendar.dateComponents([.year, .month, .day], from: anchor)
        return PlanDay(
            year: parts.year ?? 1970,
            month: parts.month ?? 1,
            day: parts.day ?? 1
        )
    }

    public func start(of day: PlanDay) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = hour
        parts.minute = 0
        parts.second = 0
        return calendar.date(from: parts) ?? dateFallback
    }

    public func end(of day: PlanDay) -> Date {
        start(of: day.advanced(by: 1))
    }

    private var dateFallback: Date { Date(timeIntervalSince1970: 0) }
}
