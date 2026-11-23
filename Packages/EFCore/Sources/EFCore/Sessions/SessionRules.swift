import Foundation

/// D-14 check-ins and auto-end; D-27 "just 5 minutes".
/// Everything is computed from timestamps, so a sleeping Mac or a relaunch gives the same answer as a timer.
public enum SessionRules {
    public static func start(taskID: UUID, mode: SessionStartMode, id: UUID = UUID(), now: Date) -> SessionSnapshot {
        SessionSnapshot(id: id, taskID: taskID, start: now, kind: .timed, startMode: mode)
    }

    /// The D-14 interval: estimate × multiplier, or the no-estimate default.
    public static func interval(estimateMinutes: Int?, settings: PlannerSettings) -> TimeInterval {
        if let estimate = estimateMinutes, estimate > 0 {
            return TimeInterval(estimate) * 60 * settings.checkInMultiplier
        }
        return TimeInterval(settings.checkInNoEstimateMinutes * 60)
    }

    /// True while the next prompt is the 5-minute "Keep going?" rather than "Still on this?".
    public static func isFiveMinutePrompt(_ session: SessionSnapshot) -> Bool {
        session.startMode == .fiveMinutes && session.checkInAnchor == nil
    }

    public static func nextCheckIn(_ session: SessionSnapshot, estimateMinutes: Int?, settings: PlannerSettings) -> Date {
        if isFiveMinutePrompt(session) {
            return session.start.addingTimeInterval(TimeInterval(settings.fiveMinuteStartMinutes * 60))
        }
        let anchor = session.checkInAnchor ?? session.start
        return anchor.addingTimeInterval(interval(estimateMinutes: estimateMinutes, settings: settings))
    }

    public enum State: Hashable, Sendable {
        case running(nextCheckIn: Date)
        /// Prompt is showing. Unanswered until `deadline` → auto-end at `checkIn`.
        case checkInDue(checkIn: Date, deadline: Date)
        /// Grace passed with no answer: end at the check-in time, `autoEnded` (excluded from the estimator).
        case shouldAutoEnd(at: Date)
        case ended
    }

    public static func state(_ session: SessionSnapshot, estimateMinutes: Int?, settings: PlannerSettings, now: Date) -> State {
        guard session.isOpen else { return .ended }
        let checkIn = nextCheckIn(session, estimateMinutes: estimateMinutes, settings: settings)
        if now < checkIn { return .running(nextCheckIn: checkIn) }
        let deadline = checkIn.addingTimeInterval(TimeInterval(settings.checkInGraceMinutes * 60))
        if now < deadline { return .checkInDue(checkIn: checkIn, deadline: deadline) }
        return .shouldAutoEnd(at: checkIn)
    }

    public enum Answer: String, Codable, Sendable, Hashable {
        /// "Yes" / "Keep going": next check-in one interval from now.
        case keepGoing
        /// "Done": session ends by the user, task completes (caller completes the task).
        case done
        /// "Stop here" / "Stop": session ends by the user, task stays open.
        case stop
    }

    public static func answer(_ session: SessionSnapshot, _ answer: Answer, now: Date) -> SessionSnapshot {
        var s = session
        switch answer {
        case .keepGoing:
            s.checkInAnchor = now
        case .done, .stop:
            s.end = now
            s.endedBy = .user
        }
        return s
    }

    public static func end(_ session: SessionSnapshot, at: Date, by: SessionEnd) -> SessionSnapshot {
        var s = session
        s.end = max(at, s.start)
        s.endedBy = by
        return s
    }

    /// Whole minutes since start, rounded down.
    public static func elapsedMinutes(_ session: SessionSnapshot, now: Date) -> Int {
        max(0, Int(((session.end ?? now).timeIntervalSince(session.start)) / 60))
    }
}

/// D-25: what the menu bar shows. Minute resolution. The app turns this into text.
public enum StatusLine {
    public enum Time: Hashable, Sendable {
        /// Minutes left on the estimate (rounded up, so it reads 1 until it's actually over).
        case remaining(Int)
        /// Past the estimate: elapsed beyond it. Shown neutrally (`+12m`), never red.
        case over(Int)
        /// Session without an estimate.
        case elapsed(Int)
        /// No session: minutes until the next event today.
        case untilEvent(Int)
    }

    public struct Label: Hashable, Sendable {
        public var taskTitle: String?
        public var time: Time?
        public var isSessionRunning: Bool
    }

    /// - Parameter nextEventStart: start of the next timed event today, if calendar access allows.
    public static func label(
        session: SessionSnapshot?,
        sessionTask: TaskSnapshot?,
        nowTask: TaskSnapshot?,
        nextEventStart: Date?,
        now: Date
    ) -> Label {
        if let session, session.isOpen, let task = sessionTask {
            let elapsedSeconds = now.timeIntervalSince(session.start)
            if let estimate = task.estimateMinutes, estimate > 0 {
                let leftSeconds = TimeInterval(estimate * 60) - elapsedSeconds
                let time: Time = leftSeconds > 0
                    ? .remaining(Int((leftSeconds / 60).rounded(.up)))
                    : .over(Int((-leftSeconds / 60).rounded(.down)))
                return Label(taskTitle: task.title, time: time, isSessionRunning: true)
            }
            return Label(taskTitle: task.title, time: .elapsed(max(0, Int(elapsedSeconds / 60))), isSessionRunning: true)
        }
        guard let nowTask else { return Label(taskTitle: nil, time: nil, isSessionRunning: false) }
        let untilEvent = nextEventStart.flatMap { start -> Time? in
            let seconds = start.timeIntervalSince(now)
            return seconds > 0 ? .untilEvent(Int((seconds / 60).rounded(.up))) : nil
        }
        return Label(taskTitle: nowTask.title, time: untilEvent, isSessionRunning: false)
    }

    /// Next timed event starting after `now` and before `dayEnd`. Pass only events that are shown (not Hidden).
    public static func nextEventStart(events: [EventSnapshot], now: Date, dayEnd: Date) -> Date? {
        events
            .filter { !$0.isAllDay && $0.start > now && $0.start < dayEnd }
            .map(\.start)
            .min()
    }
}
