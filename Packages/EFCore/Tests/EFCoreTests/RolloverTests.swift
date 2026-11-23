import Foundation
import Testing
@testable import EFCore

struct RolloverTests {
    @Test func threeFiftyNineDoesNotRollButFourOhOneDoes() {
        let tasks = [Fx.task("Invoice", must: true, order: 0)]
        let at359 = Fx.boundary.planDay(containing: Fx.utc("2026-11-21T09:59:00Z"))
        let at401 = Fx.boundary.planDay(containing: Fx.utc("2026-11-21T10:01:00Z"))
        #expect(Rollover.run(tasks: tasks, lastRolloverDay: Fx.day(20), today: at359) == nil)
        let result = Rollover.run(tasks: tasks, lastRolloverDay: Fx.day(20), today: at401)
        #expect(result?.summary.carried == 1)
        #expect(result?.changedTasks.first?.carriedFrom == Fx.day(20))
    }

    @Test func unfinishedMustsMoveToTheCarriedRow() throws {
        let must = Fx.task("Invoice", must: true, order: 0)
        let done = Fx.task("Call", must: true, order: 1, status: .done)
        let result = try #require(Rollover.run(tasks: [must, done], lastRolloverDay: Fx.day(19), today: Fx.day(20)))
        #expect(result.changedTasks.count == 1)
        let moved = try #require(result.changedTasks.first)
        #expect(moved.isTodayMust == false)
        #expect(moved.todayOrder == nil)
        #expect(moved.carriedFrom == Fx.day(19))
        #expect(moved.rolloverCount == 1)
        #expect(result.clearPin)
    }

    @Test func aNineDayGapRunsOnceAndCountsOnce() throws {
        let must = Fx.task("Invoice", must: true, order: 0)
        let first = try #require(Rollover.run(tasks: [must], lastRolloverDay: Fx.day(10), today: Fx.day(19)))
        #expect(first.changedTasks.first?.rolloverCount == 1)
        #expect(first.changedTasks.first?.carriedFrom == Fx.day(10))
        #expect(first.summary.from == Fx.day(10))
        // Marker now says 19 → a second launch the same day is a no-op.
        #expect(Rollover.run(tasks: first.changedTasks, lastRolloverDay: Fx.day(19), today: Fx.day(19)) == nil)
    }

    @Test func anIgnoredCarriedItemClearsTheNextDay() throws {
        let must = Fx.task("Invoice", must: true, order: 0)
        let day1 = try #require(Rollover.run(tasks: [must], lastRolloverDay: Fx.day(19), today: Fx.day(20)))
        let day2 = try #require(Rollover.run(tasks: day1.changedTasks, lastRolloverDay: Fx.day(20), today: Fx.day(21)))
        let task = try #require(day2.changedTasks.first)
        #expect(task.carriedFrom == nil)
        #expect(task.isTodayMust == false)
        #expect(task.rolloverCount == 1)
        #expect(day2.summary.clearedCarried == 1)
        #expect(TodayRules.inbox(tasks: [task]).map(\.id) == [task.id])
    }

    @Test func pauseDayDoesNotIncrement() throws {
        let must = Fx.task("Invoice", must: true, order: 0)
        let r = try #require(Rollover.run(tasks: [must], lastRolloverDay: Fx.day(19), previousDayMode: .pause, today: Fx.day(20)))
        #expect(r.changedTasks.first?.rolloverCount == 0)
        #expect(r.changedTasks.first?.carriedFrom == Fx.day(19))
    }

    @Test func routineInstancesExpireAndNeverCarry() throws {
        let routine = UUID()
        let old = Fx.task("Meds", must: true, routine: (routine, Fx.day(19)))
        let r = try #require(Rollover.run(tasks: [old], lastRolloverDay: Fx.day(19), today: Fx.day(20)))
        let t = try #require(r.changedTasks.first)
        #expect(t.status == .dropped)
        #expect(t.dropReason == .routineExpired)
        #expect(t.carriedFrom == nil)
        #expect(r.summary.expiredRoutines == 1)
        #expect(r.summary.carried == 0)
    }

    @Test func clockGoingBackwardsDoesNothing() {
        let must = Fx.task("Invoice", must: true)
        #expect(Rollover.run(tasks: [must], lastRolloverDay: Fx.day(21), today: Fx.day(20)) == nil)
    }

    @Test func firstEverRunCarriesFromYesterday() throws {
        let must = Fx.task("Invoice", must: true)
        let r = try #require(Rollover.run(tasks: [must], lastRolloverDay: nil, today: Fx.day(20)))
        #expect(r.changedTasks.first?.carriedFrom == Fx.day(19))
    }

    @Test func untouchedTasksAreNotRewritten() throws {
        let inbox = Fx.task("Someday thing")
        let r = try #require(Rollover.run(tasks: [inbox], lastRolloverDay: Fx.day(19), today: Fx.day(20)))
        #expect(r.changedTasks.isEmpty)
    }

    @Test func nextBoundaryIsTheComingFourAM() {
        let at = Fx.utc("2026-11-21T09:30:00Z")   // 3:30 Chicago, still plan day 20
        #expect(Rollover.nextBoundary(after: at, boundary: Fx.boundary) == Fx.utc("2026-11-21T10:00:00Z"))
        let after = Fx.utc("2026-11-21T10:00:00Z")
        #expect(Rollover.nextBoundary(after: after, boundary: Fx.boundary) == Fx.utc("2026-11-22T10:00:00Z"))
    }

    @Test func nextBoundaryAcrossDSTEnd() {
        // US DST ends 2026-11-01 at 2:00. Boundary on Nov 1 is 4:00 CST = 10:00Z; Oct 31 was 4:00 CDT = 09:00Z.
        let lateOct31 = Fx.utc("2026-11-01T06:00:00Z")   // 1:00 CDT Nov 1, plan day Oct 31
        #expect(Rollover.nextBoundary(after: lateOct31, boundary: Fx.boundary) == Fx.utc("2026-11-01T10:00:00Z"))
    }
}
