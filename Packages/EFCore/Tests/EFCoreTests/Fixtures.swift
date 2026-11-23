import Foundation
@testable import EFCore

enum Fx {
    static let zone = TimeZone(identifier: "America/Chicago")!
    static let boundary = DayBoundary(hour: 4, timeZone: zone)

    static func utc(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: iso)!
    }

    static let t0 = utc("2026-11-20T15:00:00Z")   // 9:00 Chicago

    static func task(
        _ title: String,
        must: Bool = false,
        order: Int? = nil,
        carried: PlanDay? = nil,
        status: TaskStatus = .open,
        created: Date = t0,
        estimate: Int? = nil,
        due: Date? = nil,
        someday: Bool = false,
        routine: (UUID, PlanDay)? = nil,
        bucket: UUID? = nil
    ) -> TaskSnapshot {
        TaskSnapshot(
            id: UUID(),
            title: title,
            bucketID: bucket,
            status: status,
            estimateMinutes: estimate,
            dueDate: due,
            isTodayMust: must,
            todayOrder: order,
            isSomeday: someday,
            carriedFrom: carried,
            routineID: routine?.0,
            routineDay: routine?.1,
            createdAt: created,
            lastTouchedAt: created
        )
    }

    static func day(_ d: Int, month: Int = 11) -> PlanDay { PlanDay(year: 2026, month: month, day: d) }
}
