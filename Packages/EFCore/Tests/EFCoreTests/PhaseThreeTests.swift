import Foundation
import Testing
@testable import EFCore

struct SchedulingTests {
    let settings = PlannerSettings.standard
    let day = Fx.day(20)

    private func event(_ title: String, start: Date, end: Date, allDay: Bool = false, availability: EventAvailability = .busy) -> ClassifiedEvent {
        let snapshot = EventSnapshot(
            ref: EventRef(externalID: title, occurrenceStart: start),
            calendarID: "c", title: title, start: start, end: end,
            isAllDay: allDay, availability: availability, hasLocation: false
        )
        return ClassifiedEvent(event: snapshot, mode: .busy, blocksTime: CalendarRules.blocksTime(event: snapshot, mode: .busy))
    }

    @Test func windowIsFiveToNine() {
        let window = Scheduling.window(on: day, boundary: Fx.boundary, settings: settings)
        #expect(window.start == Fx.boundary.clockTime(on: day, minutesFromMidnight: 5 * 60))
        #expect(window.end == Fx.boundary.clockTime(on: day, minutesFromMidnight: 21 * 60))
    }

    @Test func busyEventAndBufferLeaveSnappedGaps() {
        let start = Fx.boundary.clockTime(on: day, minutesFromMidnight: 10 * 60)
        let meeting = event("Dentist", start: start, end: start.addingTimeInterval(3600))
        let slots = Scheduling.freeSlots(events: [meeting], blocks: [], day: day, boundary: Fx.boundary, settings: settings)
        #expect(slots.count == 2)
        #expect(slots[0].start == Fx.boundary.clockTime(on: day, minutesFromMidnight: 5 * 60))
        #expect(slots[0].end == Fx.boundary.clockTime(on: day, minutesFromMidnight: 9 * 60 + 45))
        #expect(slots[1].start == Fx.boundary.clockTime(on: day, minutesFromMidnight: 11 * 60 + 15))
        #expect(slots[1].end == Fx.boundary.clockTime(on: day, minutesFromMidnight: 21 * 60))
    }

    @Test func visibleEventDoesNotConsumeTheGap() {
        var item = event("Birthday", start: Fx.t0, end: Fx.t0 + 3600, availability: .busy)
        item.mode = .visible
        item.blocksTime = false
        let slots = Scheduling.freeSlots(events: [item], blocks: [], day: day, boundary: Fx.boundary, settings: settings)
        #expect(slots.count == 1)
        #expect(slots[0].minutes == 16 * 60)
    }

    @Test func allDayOutOfOfficeLeavesNoGap() {
        let item = event("Away", start: Fx.t0, end: Fx.t0 + 86400, allDay: true, availability: .unavailable)
        let slots = Scheduling.freeSlots(events: [item], blocks: [], day: day, boundary: Fx.boundary, settings: settings)
        #expect(slots.isEmpty)
    }

    @Test func unresolvedBlockOccupiesTimeAndAResolvedOneDoesNot() {
        let start = Fx.boundary.clockTime(on: day, minutesFromMidnight: 14 * 60)
        let live = BlockSnapshot(id: UUID(), taskID: UUID(), start: start, end: start.addingTimeInterval(3600))
        var done = live
        done.id = UUID()
        done.resolution = .unscheduled
        let withLive = Scheduling.freeSlots(events: [], blocks: [live], day: day, boundary: Fx.boundary, settings: settings)
        let withDone = Scheduling.freeSlots(events: [], blocks: [done], day: day, boundary: Fx.boundary, settings: settings)
        #expect(withLive.count == 2)
        #expect(withDone.count == 1)
    }

    @Test func proposalUsesTheEstimateClippedToTheGap() throws {
        let gap = Scheduling.Interval(start: Fx.t0, end: Fx.t0 + 20 * 60)
        let task = Fx.task("Write", estimate: 25)
        let block = try #require(Scheduling.propose(task: task, in: gap, settings: settings))
        #expect(block.end.timeIntervalSince(block.start) == 15 * 60)
        let open = Scheduling.Interval(start: Fx.t0, end: Fx.t0 + 3 * 3600)
        let full = try #require(Scheduling.propose(task: task, in: open, settings: settings))
        #expect(full.end.timeIntervalSince(full.start) == 30 * 60)
    }

    @Test func noEstimateProposesThirtyMinutes() throws {
        let gap = Scheduling.Interval(start: Fx.t0, end: Fx.t0 + 3 * 3600)
        let block = try #require(Scheduling.propose(task: Fx.task("Write"), in: gap, settings: settings))
        #expect(block.end.timeIntervalSince(block.start) == 30 * 60)
    }
}

struct BlockRuleTests {
    let settings = PlannerSettings.standard

    @Test func passedBlockIsPendingUntilASessionOverlapsIt() {
        let task = Fx.task("Write")
        let block = BlockSnapshot(id: UUID(), taskID: task.id, start: Fx.t0 - 3600, end: Fx.t0 - 60)
        let pending = BlockRules.pending(blocks: [block], tasks: [task], sessions: [], now: Fx.t0)
        #expect(pending.map(\.id) == [block.id])
        let session = SessionSnapshot(id: UUID(), taskID: task.id, start: Fx.t0 - 1800, end: Fx.t0 - 30, kind: .timed, endedBy: .user)
        #expect(BlockRules.pending(blocks: [block], tasks: [task], sessions: [session], now: Fx.t0).isEmpty)
    }

    @Test func didItIsUnverifiedAndLeavesTheEstimator() {
        let block = BlockSnapshot(id: UUID(), taskID: UUID(), start: Fx.t0, end: Fx.t0 + 1800)
        let result = BlockRules.didIt(block)
        #expect(result.block.resolution == .didIt)
        #expect(result.session.kind == .unverified)
        #expect(result.session.isEstimatorEligible == false)
        #expect(result.session.isOpen == false)
    }

    @Test func rescheduleResolvesTheOldBlock() {
        let block = BlockSnapshot(id: UUID(), taskID: UUID(), start: Fx.t0 - 3600, end: Fx.t0 - 1800)
        let gap = Scheduling.Interval(start: Fx.t0, end: Fx.t0 + 3 * 3600)
        let moved = BlockRules.reschedule(block, into: gap, settings: settings)
        #expect(moved?.old.resolution == .rescheduled)
        #expect(moved?.new.resolution == nil)
        #expect(moved?.new.start == Fx.t0)
    }

    @Test func aResolvedBlockReturnsToTheInbox() {
        let task = Fx.task("Write")
        let block = BlockSnapshot(id: UUID(), taskID: task.id, start: Fx.t0, end: Fx.t0 + 1800, resolution: .unscheduled)
        #expect(TodayRules.inbox(tasks: [task], blocks: [block]).map(\.id) == [task.id])
        let live = BlockSnapshot(id: UUID(), taskID: task.id, start: Fx.t0, end: Fx.t0 + 1800)
        #expect(TodayRules.inbox(tasks: [task], blocks: [live]).isEmpty)
    }
}

struct RoutineRuleTests {
    @Test func fridayIsAWeekdayAndSundayIsNot() {
        let friday = PlanDay(year: 2026, month: 11, day: 20)
        let sunday = PlanDay(year: 2026, month: 11, day: 22)
        #expect(friday.weekday() == 6)
        let weekdays = RoutineTemplate(id: UUID(), title: "Dishes", schedule: .weekdays, checklist: ["Rinse"], isActive: true)
        #expect(RoutineRules.isDue(weekdays, on: friday))
        #expect(RoutineRules.isDue(weekdays, on: sunday) == false)
        var paused = weekdays
        paused.isActive = false
        #expect(RoutineRules.isDue(paused, on: friday) == false)
    }

    @Test func everyOtherDayCountsFromTheAnchor() {
        let anchor = PlanDay(year: 2026, month: 11, day: 18)
        let template = RoutineTemplate(
            id: UUID(), title: "Laundry", schedule: .everyNDays(2, anchor: anchor), checklist: [], isActive: true
        )
        #expect(RoutineRules.isDue(template, on: anchor))
        #expect(RoutineRules.isDue(template, on: anchor.advanced(by: 1)) == false)
        #expect(RoutineRules.isDue(template, on: anchor.advanced(by: 2)))
    }

    @Test func spawnOnceAndCopyTheChecklist() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let template = RoutineTemplate(id: UUID(), title: "Dishes", schedule: .daily, checklist: ["Rinse", " "], isActive: true)
        let first = RoutineRules.spawn(template, on: day, existing: [], now: Fx.t0)
        #expect(first?.task.routineDay == day)
        #expect(first?.task.isTodayMust == false)
        #expect(first?.subtasks.map(\.title) == ["Rinse"])
        let again = RoutineRules.spawn(template, on: day, existing: [first!.task], now: Fx.t0)
        #expect(again == nil)
    }

    @Test func rolloverSpawnsTodaysInstanceAndDoesNotRewriteIt() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let template = RoutineTemplate(id: UUID(), title: "Dishes", schedule: .daily, estimateMinutes: 15, checklist: ["Rinse"], isActive: true)
        let first = Rollover.run(tasks: [], routines: [template], lastRolloverDay: nil, today: day, now: Fx.t0)
        #expect(first?.spawnedTasks.map(\.title) == ["Dishes"])
        #expect(first?.spawnedSubtasks.map(\.title) == ["Rinse"])
        let existing = first!.spawnedTasks[0]
        var edited = template
        edited.title = "Wash up"
        let second = Rollover.run(tasks: [existing], routines: [edited], lastRolloverDay: day.advanced(by: -1), today: day, now: Fx.t0)
        #expect(second?.spawnedTasks.isEmpty == true)
    }
}

struct FreshStartTests {
    @Test func clearsTodayAndCarriedAndCanUndo() {
        var must = Fx.task("Invoice", must: true, order: 0)
        must.lastTouchedAt = Fx.t0
        var carried = Fx.task("Call", carried: Fx.day(19))
        carried.lastTouchedAt = Fx.t0
        let done = Fx.task("Sent", status: .done)
        let result = FreshStart.apply(tasks: [must, carried, done], moveUntouchedToSomeday: false, settings: .standard, now: Fx.t0)
        #expect(result.changedTasks.allSatisfy { !$0.isTodayMust && $0.carriedFrom == nil })
        #expect(result.changedTasks.count == 2)
        let restored = FreshStart.undo(tasks: result.changedTasks, snapshot: result.snapshot)
        #expect(restored.first { $0.id == must.id }?.isTodayMust == true)
        #expect(restored.first { $0.id == carried.id }?.carriedFrom == Fx.day(19))
    }

    @Test func untouchedTasksCanMoveToSomeday() {
        var old = Fx.task("Someday pile")
        old.lastTouchedAt = Fx.t0.addingTimeInterval(-40 * 24 * 3600)
        var recent = Fx.task("This week", must: true)
        recent.lastTouchedAt = Fx.t0
        let result = FreshStart.apply(tasks: [old, recent], moveUntouchedToSomeday: true, settings: .standard, now: Fx.t0)
        #expect(result.changedTasks.first { $0.id == old.id }?.isSomeday == true)
        #expect(result.changedTasks.first { $0.id == recent.id }?.isSomeday == false)
    }

    @Test func undoSkipsATaskThatWasFinished() {
        var must = Fx.task("Invoice", must: true)
        must.lastTouchedAt = Fx.t0
        let result = FreshStart.apply(tasks: [must], moveUntouchedToSomeday: false, settings: .standard, now: Fx.t0)
        var finished = result.changedTasks[0]
        finished.status = .done
        #expect(FreshStart.undo(tasks: [finished], snapshot: result.snapshot).isEmpty)
    }
}
