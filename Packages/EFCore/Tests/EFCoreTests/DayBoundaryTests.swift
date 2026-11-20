import Foundation
import Testing
@testable import EFCore

struct DayBoundaryTests {
    private let zone = TimeZone(identifier: "America/Chicago")!

    private func boundary() -> DayBoundary {
        DayBoundary(hour: 4, timeZone: zone)
    }

    private func utc(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let date = formatter.date(from: iso)
        #expect(date != nil)
        return date ?? Date(timeIntervalSince1970: 0)
    }

    @Test func threeFiftyNineIsThePreviousPlanDay() {
        let day = boundary().planDay(containing: utc("2026-11-20T09:59:00Z"))
        #expect(day == PlanDay(year: 2026, month: 11, day: 19))
    }

    @Test func fourOClockOpensTheNewPlanDay() {
        let day = boundary().planDay(containing: utc("2026-11-20T10:00:00Z"))
        #expect(day == PlanDay(year: 2026, month: 11, day: 20))
    }

    @Test func fourOhOneStaysOnTheNewPlanDay() {
        let day = boundary().planDay(containing: utc("2026-11-20T10:01:00Z"))
        #expect(day == PlanDay(year: 2026, month: 11, day: 20))
    }

    @Test func startAndEndMeetAtTheNextBoundary() {
        let boundary = boundary()
        let day = PlanDay(year: 2026, month: 11, day: 20)
        #expect(boundary.start(of: day) == utc("2026-11-20T10:00:00Z"))
        #expect(boundary.end(of: day) == utc("2026-11-21T10:00:00Z"))
        #expect(boundary.planDay(containing: boundary.start(of: day)) == day)
        #expect(boundary.planDay(containing: boundary.end(of: day).addingTimeInterval(-1)) == day)
    }

    @Test func springForwardBeforeFourStaysOnThePreviousPlanDay() {
        let boundary = boundary()
        // 1:30 AM CST, before the jump, and 3:30 AM CDT, after it. Both are before 4:00.
        #expect(boundary.planDay(containing: utc("2026-03-08T07:30:00Z")) == PlanDay(year: 2026, month: 3, day: 7))
        #expect(boundary.planDay(containing: utc("2026-03-08T08:30:00Z")) == PlanDay(year: 2026, month: 3, day: 7))
        #expect(boundary.planDay(containing: utc("2026-03-08T09:00:00Z")) == PlanDay(year: 2026, month: 3, day: 8))
    }

    @Test func fallBackBothOneThirtiesBelongToThePreviousPlanDay() {
        let boundary = boundary()
        // 1:30 AM CDT and 1:30 AM CST on the repeated hour.
        #expect(boundary.planDay(containing: utc("2026-11-01T06:30:00Z")) == PlanDay(year: 2026, month: 10, day: 31))
        #expect(boundary.planDay(containing: utc("2026-11-01T07:30:00Z")) == PlanDay(year: 2026, month: 10, day: 31))
        #expect(boundary.planDay(containing: utc("2026-11-01T10:01:00Z")) == PlanDay(year: 2026, month: 11, day: 1))
    }

    @Test func planDayOrdersAndAdvancesAcrossAMonth() {
        let last = PlanDay(year: 2026, month: 1, day: 31)
        #expect(last.advanced(by: 1) == PlanDay(year: 2026, month: 2, day: 1))
        #expect(last < last.advanced(by: 1))
    }

    @Test func clockBuildsTheBoundaryItIsAskedFor() {
        let clock = FixedClock(now: utc("2026-11-20T09:59:00Z"), timeZone: zone)
        #expect(clock.boundary(hour: 4).planDay(containing: clock.now) == PlanDay(year: 2026, month: 11, day: 19))
    }
}
