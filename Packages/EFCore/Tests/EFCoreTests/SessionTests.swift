import Foundation
import Testing
@testable import EFCore

struct SessionTests {
    let settings = PlannerSettings.standard
    let task = UUID()

    @Test func checkInWithEstimateIsOneAndAHalfTimes() {
        let s = SessionRules.start(taskID: task, mode: .standard, now: Fx.t0)
        #expect(SessionRules.nextCheckIn(s, estimateMinutes: 20, settings: settings) == Fx.t0 + 30 * 60)
    }

    @Test func checkInWithoutEstimateIsFortyFive() {
        let s = SessionRules.start(taskID: task, mode: .standard, now: Fx.t0)
        #expect(SessionRules.nextCheckIn(s, estimateMinutes: nil, settings: settings) == Fx.t0 + 45 * 60)
    }

    @Test func keepGoingRestartsTheInterval() {
        let s = SessionRules.start(taskID: task, mode: .standard, now: Fx.t0)
        let answered = SessionRules.answer(s, .keepGoing, now: Fx.t0 + 50 * 60)
        #expect(SessionRules.nextCheckIn(answered, estimateMinutes: nil, settings: settings) == Fx.t0 + 95 * 60)
    }

    @Test func stateMovesRunningDueAutoEnd() {
        let s = SessionRules.start(taskID: task, mode: .standard, now: Fx.t0)
        let checkIn = Fx.t0 + 45 * 60
        #expect(SessionRules.state(s, estimateMinutes: nil, settings: settings, now: Fx.t0 + 60) == .running(nextCheckIn: checkIn))
        #expect(SessionRules.state(s, estimateMinutes: nil, settings: settings, now: checkIn) == .checkInDue(checkIn: checkIn, deadline: checkIn + 45 * 60))
        #expect(SessionRules.state(s, estimateMinutes: nil, settings: settings, now: checkIn + 45 * 60) == .shouldAutoEnd(at: checkIn))
    }

    @Test func sleepingPastGraceAutoEndsAtTheCheckInTime() {
        let s = SessionRules.start(taskID: task, mode: .standard, now: Fx.t0)
        let wake = Fx.t0 + 8 * 3600
        guard case let .shouldAutoEnd(at) = SessionRules.state(s, estimateMinutes: 30, settings: settings, now: wake) else {
            Issue.record("expected auto-end"); return
        }
        let ended = SessionRules.end(s, at: at, by: .autoEnded)
        #expect(ended.end == Fx.t0 + 45 * 60)
        #expect(ended.isEstimatorEligible == false)
    }

    @Test func fiveMinuteStartPromptsAtFive() {
        let s = SessionRules.start(taskID: task, mode: .fiveMinutes, now: Fx.t0)
        #expect(SessionRules.isFiveMinutePrompt(s))
        #expect(SessionRules.nextCheckIn(s, estimateMinutes: 60, settings: settings) == Fx.t0 + 5 * 60)
        let kept = SessionRules.answer(s, .keepGoing, now: Fx.t0 + 6 * 60)
        #expect(!SessionRules.isFiveMinutePrompt(kept))
        #expect(SessionRules.nextCheckIn(kept, estimateMinutes: 60, settings: settings) == Fx.t0 + 6 * 60 + 90 * 60)
    }

    @Test func fiveMinuteStopIsNotEstimatorData() {
        let s = SessionRules.start(taskID: task, mode: .fiveMinutes, now: Fx.t0)
        let stopped = SessionRules.answer(s, .stop, now: Fx.t0 + 5 * 60)
        #expect(stopped.endedBy == .user)
        #expect(stopped.isEstimatorEligible == false)
        let kept = SessionRules.answer(s, .keepGoing, now: Fx.t0 + 5 * 60)
        #expect(SessionRules.answer(kept, .done, now: Fx.t0 + 40 * 60).isEstimatorEligible)
    }

    @Test func userEndedStandardSessionIsEligible() {
        let s = SessionRules.start(taskID: task, mode: .standard, now: Fx.t0)
        #expect(SessionRules.answer(s, .done, now: Fx.t0 + 600).isEstimatorEligible)
        #expect(SessionRules.end(s, at: Fx.t0 + 600, by: .appQuit).isEstimatorEligible == false)
    }
}

struct StatusLineTests {
    let settings = PlannerSettings.standard

    @Test func runningSessionCountsDownToTheCheckIn() {
        let t = Fx.task("Write", estimate: 25)
        let s = SessionRules.start(taskID: t.id, mode: .standard, now: Fx.t0)
        let checkIn = SessionRules.nextCheckIn(s, estimateMinutes: t.estimateMinutes, settings: settings)
        let early = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextCheckIn: checkIn, nextEventStart: nil, now: Fx.t0 + 30)
        #expect(early.time == .untilCheckIn(37))
        let lastMinute = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextCheckIn: checkIn, nextEventStart: nil, now: checkIn - 59)
        #expect(lastMinute.time == .untilCheckIn(1))
        let due = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextCheckIn: checkIn, nextEventStart: nil, now: checkIn)
        #expect(due.time == .checkInDue)
        #expect(due.isSessionRunning)
    }

    @Test func fiveMinuteSessionCountsDownFromFive() {
        let t = Fx.task("Write")
        let s = SessionRules.start(taskID: t.id, mode: .fiveMinutes, now: Fx.t0)
        let checkIn = SessionRules.nextCheckIn(s, estimateMinutes: nil, settings: settings)
        let label = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextCheckIn: checkIn, nextEventStart: nil, now: Fx.t0)
        #expect(label.time == .untilCheckIn(5))
    }

    @Test func noSessionShowsNextEventOrJustTheTitle() {
        let t = Fx.task("Write")
        let withEvent = StatusLine.label(session: nil, sessionTask: nil, nowTask: t, nextCheckIn: nil, nextEventStart: Fx.t0 + 20 * 60, now: Fx.t0)
        #expect(withEvent == .init(taskTitle: "Write", time: .untilEvent(20), isSessionRunning: false))
        let without = StatusLine.label(session: nil, sessionTask: nil, nowTask: t, nextCheckIn: nil, nextEventStart: nil, now: Fx.t0)
        #expect(without.time == nil)
        let nothing = StatusLine.label(session: nil, sessionTask: nil, nowTask: nil, nextCheckIn: nil, nextEventStart: nil, now: Fx.t0)
        #expect(nothing.taskTitle == nil)
    }

    @Test func nextEventSkipsAllDayAndPast() {
        func ev(_ start: Date, allDay: Bool = false) -> EventSnapshot {
            EventSnapshot(ref: EventRef(externalID: UUID().uuidString, occurrenceStart: start), calendarID: "c", title: "e",
                          start: start, end: start + 1800, isAllDay: allDay, availability: .busy, hasLocation: false)
        }
        let events = [ev(Fx.t0 - 60), ev(Fx.t0 + 600, allDay: true), ev(Fx.t0 + 1200), ev(Fx.t0 + 3600)]
        #expect(StatusLine.nextEventStart(events: events, now: Fx.t0, dayEnd: Fx.t0 + 86400) == Fx.t0 + 1200)
    }
}
