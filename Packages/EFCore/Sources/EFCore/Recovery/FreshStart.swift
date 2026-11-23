import Foundation

/// D-15. Clears Today and the carried flag. Blocks, sessions, the pin, and finished tasks stay.
public enum FreshStart {
    public struct Fields: Codable, Hashable, Sendable {
        public var isTodayMust: Bool
        public var todayOrder: Int?
        public var carriedFrom: PlanDay?
        public var isSomeday: Bool

        public init(task: TaskSnapshot) {
            isTodayMust = task.isTodayMust
            todayOrder = task.todayOrder
            carriedFrom = task.carriedFrom
            isSomeday = task.isSomeday
        }
    }

    public struct Result: Hashable, Sendable {
        public var changedTasks: [TaskSnapshot]
        /// Every open task, so undo can put the fields back.
        public var snapshot: [UUID: Fields]
    }

    public static func apply(
        tasks: [TaskSnapshot],
        moveUntouchedToSomeday: Bool,
        settings: PlannerSettings,
        now: Date
    ) -> Result {
        let cutoff = now.addingTimeInterval(TimeInterval(-settings.somedayAfterDays * 24 * 60 * 60))
        var changed: [TaskSnapshot] = []
        var snapshot: [UUID: Fields] = [:]
        for task in tasks where task.status == .open {
            snapshot[task.id] = Fields(task: task)
            var copy = task
            copy.isTodayMust = false
            copy.todayOrder = nil
            copy.carriedFrom = nil
            if moveUntouchedToSomeday, task.lastTouchedAt <= cutoff {
                copy.isSomeday = true
            }
            if copy != task {
                copy.lastTouchedAt = now
                changed.append(copy)
            }
        }
        return Result(changedTasks: changed, snapshot: snapshot)
    }

    /// Restores the four fields on tasks that are still open. A task finished since the snapshot is left alone.
    public static func undo(tasks: [TaskSnapshot], snapshot: [UUID: Fields]) -> [TaskSnapshot] {
        tasks.compactMap { task in
            guard task.status == .open, let fields = snapshot[task.id] else { return nil }
            var copy = task
            copy.isTodayMust = fields.isTodayMust
            copy.todayOrder = fields.todayOrder
            copy.carriedFrom = fields.carriedFrom
            copy.isSomeday = fields.isSomeday
            return copy == task ? nil : copy
        }
    }
}
