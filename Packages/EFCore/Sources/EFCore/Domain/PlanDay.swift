import Foundation

/// A calendar date in the plan-day sense: the civil date of the boundary
/// that opened the day, not midnight.
public struct PlanDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: PlanDay, rhs: PlanDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func advanced(by days: Int) -> PlanDay {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        guard
            let date = gregorian.date(from: parts),
            let shifted = gregorian.date(byAdding: .day, value: days, to: date)
        else {
            return self
        }
        let next = gregorian.dateComponents([.year, .month, .day], from: shifted)
        return PlanDay(
            year: next.year ?? year,
            month: next.month ?? month,
            day: next.day ?? day
        )
    }
}
