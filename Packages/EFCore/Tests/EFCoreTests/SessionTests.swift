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
    @Test func estimateCountsDownThenShowsOver() {
        let t = Fx.task("Write", estimate: 25)
        let s = SessionRules.start(taskID: t.id, mode: .standard, now: Fx.t0)
        let early = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextEventStart: nil, now: Fx.t0 + 30)
        #expect(early.time == .remaining(25))
        let lastSeconds = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextEventStart: nil, now: Fx.t0 + 24 * 60 + 59)
        #expect(lastSeconds.time == .remaining(1))
        let over = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextEventStart: nil, now: Fx.t0 + 37 * 60 + 10)
        #expect(over.time == .over(12))
        #expect(over.isSessionRunning)
    }

    @Test func noEstimateShowsElapsed() {
        let t = Fx.task("Write")
        let s = SessionRules.start(taskID: t.id, mode: .standard, now: Fx.t0)
        let l = StatusLine.label(session: s, sessionTask: t, nowTask: t, nextEventStart: nil, now: Fx.t0 + 7 * 60 + 59)
        #expect(l.time == .elapsed(7))
    }

    @Test func noSessionShowsNextEventOrJustTheTitle() {
        let t = Fx.task("Write")
        let withEvent = StatusLine.label(session: nil, sessionTask: nil, nowTask: t, nextEventStart: Fx.t0 + 20 * 60, now: Fx.t0)
        #expect(withEvent == .init(taskTitle: "Write", time: .untilEvent(20), isSessionRunning: false))
        let without = StatusLine.label(session: nil, sessionTask: nil, nowTask: t, nextEventStart: nil, now: Fx.t0)
        #expect(without.time == nil)
        let nothing = StatusLine.label(session: nil, sessionTask: nil, nowTask: nil, nextEventStart: nil, now: Fx.t0)
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
