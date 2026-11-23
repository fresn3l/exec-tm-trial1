import Foundation

/// Derived lists (D-03, D-06, D-07). Nothing here is stored.
public enum TodayRules {
    /// D-03: open, no bucket, not a must, no block, not a routine instance, not Someday, not carried.
    /// Newest first.
    public static func inbox(tasks: [TaskSnapshot], blocks: [BlockSnapshot] = []) -> [TaskSnapshot] {
        let blocked = Set(blocks.map(\.taskID))
        return tasks
            .filter {
                $0.status == .open
                    && $0.bucketID == nil
                    && !$0.isTodayMust
                    && !blocked.contains($0.id)
                    && $0.routineID == nil
                    && !$0.isSomeday
                    && $0.carriedFrom == nil
            }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }

    /// Open Today musts in order.
    public static func musts(tasks: [TaskSnapshot]) -> [TaskSnapshot] {
        tasks
            .filter { $0.status == .open && $0.isTodayMust }
            .sorted(by: mustOrder)
    }

    /// Musts finished today (shown struck through under the open ones).
    public static func doneToday(tasks: [TaskSnapshot], today: PlanDay, boundary: DayBoundary) -> [TaskSnapshot] {
        let start = boundary.start(of: today)
        return tasks
            .filter { $0.status == .done && ($0.completedAt ?? .distantPast) >= start }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    public struct CarriedRow: Hashable, Sendable {
        public var visible: [TaskSnapshot]
        public var moreCount: Int
        public var all: [TaskSnapshot]
        public var isEmpty: Bool { all.isEmpty }
    }

    /// D-06: at most 3 visible, then "+N more". Hidden on pause days. Routine instances never appear.
    public static func carriedRow(tasks: [TaskSnapshot], dayMode: DayMode = .ideal, visibleLimit: Int = 3) -> CarriedRow {
        guard dayMode != .pause else { return CarriedRow(visible: [], moreCount: 0, all: []) }
        let all = tasks
            .filter { $0.status == .open && $0.carriedFrom != nil && $0.routineID == nil }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let visible = Array(all.prefix(visibleLimit))
        return CarriedRow(visible: visible, moreCount: all.count - visible.count, all: all)
    }

    /// D-07 + D-16. Energy and day modes arrive in Phase 4a; until then this is `todayCap`.
    public static func cap(settings: PlannerSettings, energy: DayEnergy? = nil) -> Int {
        switch energy {
        case .low: 1
        case .high: settings.todayCap + 1
        case .normal, nil: settings.todayCap
        }
    }

    public enum MustCheck: Hashable, Sendable {
        case ok
        /// "Today already has N. Swap one?" The user may proceed anyway.
        case overCap(current: Int, cap: Int)
    }

    public static func checkAddingMust(tasks: [TaskSnapshot], settings: PlannerSettings, energy: DayEnergy? = nil) -> MustCheck {
        let current = musts(tasks: tasks).count
        let cap = cap(settings: settings, energy: energy)
        return current < cap ? .ok : .overCap(current: current, cap: cap)
    }

    static func mustOrder(_ a: TaskSnapshot, _ b: TaskSnapshot) -> Bool {
        let ao = a.todayOrder ?? Int.max, bo = b.todayOrder ?? Int.max
        if ao != bo { return ao < bo }
        return (a.createdAt, a.id.uuidString) < (b.createdAt, b.id.uuidString)
    }
}

/// Single-task edits. Each returns the new snapshot; the repository saves it.
public enum TaskCommands {
    public static func capture(title: String, id: UUID = UUID(), now: Date) -> TaskSnapshot? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TaskSnapshot(id: id, title: trimmed, createdAt: now, lastTouchedAt: now)
    }

    /// Adds to the end of Today. The cap prompt (D-07) is the caller's job, before this.
    public static func makeMust(_ task: TaskSnapshot, among tasks: [TaskSnapshot], now: Date) -> TaskSnapshot {
        var t = task
        let lastOrder = TodayRules.musts(tasks: tasks).compactMap(\.todayOrder).max() ?? -1
        t.isTodayMust = true
        t.todayOrder = lastOrder + 1
        t.carriedFrom = nil
        t.isSomeday = false
        t.lastTouchedAt = now
        return t
    }

    public static func clearMust(_ task: TaskSnapshot, now: Date) -> TaskSnapshot {
        var t = task
        t.isTodayMust = false
        t.todayOrder = nil
        t.lastTouchedAt = now
        return t
    }

    public enum Triage: String, Codable, Sendable, Hashable { case today, later, drop }

    /// D-06 row actions. `.today` goes through the cap prompt first.
    public static func triage(_ task: TaskSnapshot, _ action: Triage, among tasks: [TaskSnapshot], now: Date) -> TaskSnapshot {
        switch action {
        case .today:
            return makeMust(task, among: tasks, now: now)
        case .later:
            var t = task
            t.carriedFrom = nil
            t.lastTouchedAt = now
            return t
        case .drop:
            return drop(task, now: now)
        }
    }

    public static func complete(_ task: TaskSnapshot, now: Date) -> TaskSnapshot {
        var t = task
        t.status = .done
        t.completedAt = now
        t.isTodayMust = false
        t.carriedFrom = nil
        t.lastTouchedAt = now
        return t
    }

    public static func drop(_ task: TaskSnapshot, now: Date) -> TaskSnapshot {
        var t = task
        t.status = .dropped
        t.dropReason = .user
        t.isTodayMust = false
        t.todayOrder = nil
        t.carriedFrom = nil
        t.lastTouchedAt = now
        return t
    }

    public static func edit(
        _ task: TaskSnapshot,
        title: String? = nil,
        firstStep: String?? = nil,
        estimateMinutes: Int?? = nil,
        now: Date
    ) -> TaskSnapshot {
        var t = task
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { t.title = trimmed }
        }
        if let firstStep {
            let trimmed = firstStep?.trimmingCharacters(in: .whitespacesAndNewlines)
            t.firstStep = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        if let estimateMinutes {
            t.estimateMinutes = estimateMinutes.flatMap { $0 > 0 ? $0 : nil }
        }
        t.lastTouchedAt = now
        return t
    }
}
