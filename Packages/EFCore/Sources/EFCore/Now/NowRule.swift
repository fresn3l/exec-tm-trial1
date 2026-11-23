import Foundation

/// D-08: deterministic Now / Next. First match wins.
public enum NowRule {
    public enum Source: String, Hashable, Sendable {
        case session         // 1. running work session
        case pinned          // 2. "Make this Now"
        case currentBlock    // 3. time block covering now
        case must            // 4. first unfinished Today must
        case upcomingBlock   // 5. block starting within the lookahead
    }

    public struct Pick: Hashable, Sendable {
        public var taskID: UUID
        public var source: Source
    }

    public struct Result: Hashable, Sendable {
        public var now: Pick?
        public var next: Pick?
        /// 6. Empty state: up to 3 "Pick one" candidates (musts, then due-soonest, then oldest).
        public var candidates: [UUID]
        /// The stored pin points at a task that is no longer open; the caller should clear it.
        public var pinIsStale: Bool
    }

    public static func evaluate(
        tasks: [TaskSnapshot],
        blocks: [BlockSnapshot] = [],
        sessions: [SessionSnapshot],
        pinnedTaskID: UUID?,
        settings: PlannerSettings,
        now: Date
    ) -> Result {
        let open = Dictionary(
            tasks.filter { $0.status == .open }.map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let pinIsStale = pinnedTaskID.map { open[$0] == nil } ?? false
        let first = match(open: open, blocks: blocks, sessions: sessions, pin: pinnedTaskID, settings: settings, now: now, excluding: [])
        let next = first.flatMap {
            match(open: open, blocks: blocks, sessions: sessions, pin: pinnedTaskID, settings: settings, now: now, excluding: [$0.taskID])
        }
        let candidates = first == nil ? pickCandidates(open: Array(open.values)) : []
        return Result(now: first, next: next, candidates: candidates, pinIsStale: pinIsStale)
    }

    private static func match(
        open: [UUID: TaskSnapshot],
        blocks: [BlockSnapshot],
        sessions: [SessionSnapshot],
        pin: UUID?,
        settings: PlannerSettings,
        now: Date,
        excluding: Set<UUID>
    ) -> Pick? {
        func usable(_ id: UUID) -> Bool { open[id] != nil && !excluding.contains(id) }

        // 1. Running session (latest start wins if there were ever two).
        if let s = sessions
            .filter({ $0.isOpen && usable($0.taskID) })
            .max(by: { $0.start < $1.start }) {
            return Pick(taskID: s.taskID, source: .session)
        }
        // 2. Pin.
        if let pin, usable(pin) { return Pick(taskID: pin, source: .pinned) }

        let liveBlocks = blocks.filter { $0.resolution == nil && usable($0.taskID) }
        // 3. Block covering now (timed routine instances join here in Phase 3).
        if let b = liveBlocks
            .filter({ $0.start <= now && now < $0.end })
            .min(by: { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }) {
            return Pick(taskID: b.taskID, source: .currentBlock)
        }
        // 4. First unfinished must.
        if let m = TodayRules.musts(tasks: Array(open.values)).first(where: { usable($0.id) }) {
            return Pick(taskID: m.id, source: .must)
        }
        // 5. Block starting within the lookahead.
        let horizon = now.addingTimeInterval(TimeInterval(settings.nowLookaheadMinutes * 60))
        if let b = liveBlocks
            .filter({ $0.start > now && $0.start <= horizon })
            .min(by: { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }) {
            return Pick(taskID: b.taskID, source: .upcomingBlock)
        }
        return nil
    }

    private static func pickCandidates(open: [TaskSnapshot]) -> [UUID] {
        let pool = open.filter { !$0.isSomeday && $0.routineID == nil }
        var out: [UUID] = []
        func add(_ list: [TaskSnapshot]) {
            for t in list where out.count < 3 && !out.contains(t.id) { out.append(t.id) }
        }
        add(TodayRules.musts(tasks: pool))
        add(pool.filter { $0.dueDate != nil }.sorted {
            ($0.dueDate!, $0.id.uuidString) < ($1.dueDate!, $1.id.uuidString)
        })
        add(pool.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) })
        return out
    }
}
