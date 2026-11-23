import Foundation

/// D-05 / D-06 / D-20. Pure: takes snapshots, returns what to change.
/// The repository applies `changedTasks` and the `rolledOverAt` marker in one save.
public enum Rollover {
    public struct Summary: Hashable, Sendable {
        public var from: PlanDay?
        public var to: PlanDay
        public var carried: Int
        public var clearedCarried: Int
        public var expiredRoutines: Int
    }

    public struct Result: Hashable, Sendable {
        /// Tasks whose fields changed. Only these need writing.
        public var changedTasks: [TaskSnapshot]
        /// Today's routine instances, created in the same save (D-20).
        public var spawnedTasks: [TaskSnapshot]
        public var spawnedSubtasks: [SubtaskSnapshot]
        /// D-08: yesterday's pin must not outrank today's musts.
        public var clearPin: Bool
        public var summary: Summary
    }

    /// - Parameters:
    ///   - lastRolloverDay: the latest day already rolled over, or `nil` on first run.
    ///   - previousDayMode: mode of `lastRolloverDay`; `.pause` skips the `rolloverCount` increment.
    /// - Returns: `nil` when there's nothing to do (already ran today, or the clock went backwards).
    public static func run(
        tasks: [TaskSnapshot],
        routines: [RoutineTemplate] = [],
        lastRolloverDay: PlanDay?,
        previousDayMode: DayMode = .ideal,
        today: PlanDay,
        now: Date = Date()
    ) -> Result? {
        if let lastRolloverDay, lastRolloverDay >= today { return nil }
        let previous = lastRolloverDay ?? today.advanced(by: -1)
        let countsAsDay = previousDayMode != .pause

        var changed: [TaskSnapshot] = []
        var carried = 0, cleared = 0, expired = 0

        for original in tasks where original.status == .open {
            var task = original

            // 1. Routine instances from earlier days expire. They never carry (D-20).
            if task.routineID != nil {
                if let day = task.routineDay, day < today {
                    task.status = .dropped
                    task.dropReason = .routineExpired
                    task.isTodayMust = false
                    task.carriedFrom = nil
                    expired += 1
                }
                if task != original { changed.append(task) }
                continue
            }

            // 2. Untouched carried items become Later. They never pile up in the row (D-06).
            if task.carriedFrom != nil {
                task.carriedFrom = nil
                cleared += 1
            }

            // 3. Unfinished musts move to the "From yesterday" row.
            if task.isTodayMust {
                task.isTodayMust = false
                task.todayOrder = nil
                task.carriedFrom = previous
                if countsAsDay { task.rolloverCount += 1 }
                carried += 1
            }

            if task != original { changed.append(task) }
        }

        // 4. Spawn today's routine instances. An existing instance for this day is left as it is.
        var spawned: [TaskSnapshot] = []
        var subtasks: [SubtaskSnapshot] = []
        let known = tasks + changed
        for template in routines {
            guard let instance = RoutineRules.spawn(template, on: today, existing: known, now: now) else { continue }
            spawned.append(instance.task)
            subtasks.append(contentsOf: instance.subtasks)
        }

        return Result(
            changedTasks: changed,
            spawnedTasks: spawned,
            spawnedSubtasks: subtasks,
            clearPin: true,
            summary: Summary(
                from: lastRolloverDay,
                to: today,
                carried: carried,
                clearedCarried: cleared,
                expiredRoutines: expired
            )
        )
    }

    /// The next instant rollover should run: the next `dayBoundaryHour` after `now`.
    public static func nextBoundary(after now: Date, boundary: DayBoundary) -> Date {
        boundary.end(of: boundary.planDay(containing: now))
    }
}
