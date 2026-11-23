import Foundation

/// D-20. A template spawns one task per due plan day. Editing the template does not rewrite it.
public enum RoutineRules {
    public static func isDue(_ template: RoutineTemplate, on day: PlanDay) -> Bool {
        guard template.isActive else { return false }
        switch template.schedule {
        case .daily:
            return true
        case .weekdays:
            let weekday = day.weekday()
            return (2...6).contains(weekday)
        case let .weekly(days):
            return days.contains(day.weekday())
        case let .everyNDays(n, anchor):
            guard n > 0, day >= anchor else { return false }
            return anchor.daysUntil(day) % n == 0
        }
    }

    /// Nil when this template already has an instance for `day`, whatever its status.
    public static func spawn(
        _ template: RoutineTemplate,
        on day: PlanDay,
        existing: [TaskSnapshot],
        now: Date,
        taskID: UUID = UUID()
    ) -> (task: TaskSnapshot, subtasks: [SubtaskSnapshot])? {
        guard isDue(template, on: day) else { return nil }
        let already = existing.contains { $0.routineID == template.id && $0.routineDay == day }
        guard !already else { return nil }
        let task = TaskSnapshot(
            id: taskID,
            title: template.title,
            bucketID: template.bucketID,
            estimateMinutes: template.estimateMinutes,
            energy: template.energy,
            routineID: template.id,
            routineDay: day,
            createdAt: now,
            lastTouchedAt: now
        )
        let subtasks = template.checklist.enumerated().compactMap { index, line -> SubtaskSnapshot? in
            let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return SubtaskSnapshot(id: UUID(), taskID: taskID, title: title, order: index)
        }
        return (task, subtasks)
    }
}
