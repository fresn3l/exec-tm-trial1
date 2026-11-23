import Foundation

/// D-12. A block whose time has passed gets one prompt, then a resolution so it never asks again.
public enum BlockRules {
    /// Earliest first. A session that overlaps the block counts as the work having happened.
    public static func pending(
        blocks: [BlockSnapshot],
        tasks: [TaskSnapshot],
        sessions: [SessionSnapshot],
        now: Date
    ) -> [BlockSnapshot] {
        let open = Set(tasks.filter { $0.status == .open }.map(\.id))
        return blocks
            .filter { block in
                block.resolution == nil
                    && block.end < now
                    && open.contains(block.taskID)
                    && !sessions.contains { overlaps($0, block, now: now) }
            }
            .sorted { ($0.end, $0.id.uuidString) < ($1.end, $1.id.uuidString) }
    }

    public static func overlaps(_ session: SessionSnapshot, _ block: BlockSnapshot, now: Date) -> Bool {
        let sessionEnd = session.end ?? now
        return session.start < block.end && sessionEnd > block.start
    }

    public static func leave(_ block: BlockSnapshot) -> BlockSnapshot {
        var copy = block
        copy.resolution = .unscheduled
        return copy
    }

    /// Records the block as done without starting a live timer. Excluded from the estimator.
    public static func didIt(_ block: BlockSnapshot, id: UUID = UUID()) -> (block: BlockSnapshot, session: SessionSnapshot) {
        var copy = block
        copy.resolution = .didIt
        let session = SessionSnapshot(
            id: id,
            taskID: block.taskID,
            start: block.start,
            end: block.end,
            kind: .unverified,
            endedBy: .user
        )
        return (copy, session)
    }

    /// The old block is resolved. The new one keeps the same length when the gap allows it.
    public static func reschedule(
        _ block: BlockSnapshot,
        into gap: Scheduling.Interval,
        settings: PlannerSettings,
        id: UUID = UUID()
    ) -> (old: BlockSnapshot, new: BlockSnapshot)? {
        let length = max(1, Int(block.end.timeIntervalSince(block.start) / 60))
        let standIn = TaskSnapshot(
            id: block.taskID, title: "", estimateMinutes: length, createdAt: block.start, lastTouchedAt: block.start
        )
        guard let proposed = Scheduling.propose(task: standIn, in: gap, settings: settings, id: id) else { return nil }
        var old = block
        old.resolution = .rescheduled
        return (old, proposed)
    }
}
