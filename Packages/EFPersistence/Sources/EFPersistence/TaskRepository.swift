import EFCore
import Foundation
import SwiftData

@MainActor
public final class TaskRepository {
    /// D-01: the app's one context. Views read the same objects through `@Query`.
    public let context: ModelContext
    /// A context doesn't keep its container alive; dropping the container while
    /// the context is in use traps. The repository holds it for as long as it lives.
    private let container: ModelContainer

    public init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    /// Uses the container's main context, never a private one.
    public convenience init(container: ModelContainer) {
        self.init(context: container.mainContext)
    }

    // MARK: Bulk reads

    public func allTasks() throws -> [TaskSnapshot] {
        try context.fetch(FetchDescriptor<TaskModel>()).map(SnapshotMapper.task(from:))
    }

    /// Open tasks plus anything finished since `since` (for "done today").
    public func workingSet(since: Date) throws -> [TaskSnapshot] {
        let open = TaskStatus.open.rawValue
        let cutoff = since
        let descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate {
            $0.statusRaw == open || ($0.completedAt ?? cutoff) > cutoff
        })
        return try context.fetch(descriptor).map(SnapshotMapper.task(from:))
    }

    public func openSessions() throws -> [SessionSnapshot] {
        let descriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.end == nil })
        return try context.fetch(descriptor).map(SnapshotMapper.session(from:))
    }

    public func blocks(from start: Date, to end: Date) throws -> [BlockSnapshot] {
        let s = start, e = end
        let descriptor = FetchDescriptor<BlockModel>(predicate: #Predicate { $0.end > s && $0.start < e })
        return try context.fetch(descriptor).map(SnapshotMapper.block(from:))
    }

    // MARK: Writes

    /// Writes several snapshots in one save.
    public func save(tasks: [TaskSnapshot] = [], sessions: [SessionSnapshot] = []) throws {
        for task in tasks {
            let model = try fetchTask(id: task.id) ?? insert(TaskModel())
            try SnapshotMapper.apply(task, to: model)
        }
        for session in sessions {
            let model = try fetchSession(id: session.id) ?? insert(SessionModel())
            SnapshotMapper.apply(session, to: model)
        }
        try context.save()
    }

    // MARK: Rollover (D-05)

    /// The latest plan day whose `rolledOverAt` is set.
    public func lastRolloverDay() throws -> PlanDay? {
        var descriptor = FetchDescriptor<DayPlanModel>(
            predicate: #Predicate { $0.rolledOverAt != nil },
            sortBy: [SortDescriptor(\.year, order: .reverse), SortDescriptor(\.month, order: .reverse), SortDescriptor(\.day, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map { PlanDay(year: $0.year, month: $0.month, day: $0.day) }
    }

    public func dayPlan(for day: PlanDay) throws -> DayPlanSnapshot? {
        try fetchDayPlan(day).map(SnapshotMapper.dayPlan(from:))
    }

    /// Loads, runs `Rollover`, and writes the task changes and today's marker in **one** save,
    /// so a crash can't leave changes without a marker (which would roll over twice).
    @discardableResult
    public func rollOverIfNeeded(today: PlanDay, now: Date) throws -> Rollover.Result? {
        let last = try lastRolloverDay()
        let previousMode = try last.flatMap(dayPlan(for:))?.mode ?? .ideal
        guard let result = Rollover.run(
            tasks: try allTasks(),
            lastRolloverDay: last,
            previousDayMode: previousMode,
            today: today
        ) else { return nil }
        for task in result.changedTasks {
            guard let model = try fetchTask(id: task.id) else { continue }
            try SnapshotMapper.apply(task, to: model)
        }
        let plan = try fetchDayPlan(today) ?? {
            let m = insert(DayPlanModel())
            m.year = today.year
            m.month = today.month
            m.day = today.day
            return m
        }()
        plan.rolledOverAt = now
        try context.save()
        return result
    }

    public func upsert(_ snapshot: TaskSnapshot) throws {
        let model = try fetchTask(id: snapshot.id) ?? insert(TaskModel())
        try SnapshotMapper.apply(snapshot, to: model)
        try context.save()
    }

    public func task(id: UUID) throws -> TaskSnapshot? {
        guard let model = try fetchTask(id: id) else { return nil }
        return try SnapshotMapper.task(from: model)
    }

    public func upsert(_ snapshot: BlockSnapshot) throws {
        let model = try fetchBlock(id: snapshot.id) ?? insert(BlockModel())
        SnapshotMapper.apply(snapshot, to: model)
        try context.save()
    }

    public func block(id: UUID) throws -> BlockSnapshot? {
        guard let model = try fetchBlock(id: id) else { return nil }
        return SnapshotMapper.block(from: model)
    }

    public func upsert(_ snapshot: SessionSnapshot) throws {
        let model = try fetchSession(id: snapshot.id) ?? insert(SessionModel())
        SnapshotMapper.apply(snapshot, to: model)
        try context.save()
    }

    public func session(id: UUID) throws -> SessionSnapshot? {
        guard let model = try fetchSession(id: id) else { return nil }
        return SnapshotMapper.session(from: model)
    }

    public func upsert(_ snapshot: RoutineTemplate) throws {
        let model = try fetchRoutine(id: snapshot.id) ?? insert(RoutineModel())
        try SnapshotMapper.apply(snapshot, to: model)
        try context.save()
    }

    public func routine(id: UUID) throws -> RoutineTemplate? {
        guard let model = try fetchRoutine(id: id) else { return nil }
        return try SnapshotMapper.routine(from: model)
    }

    private func insert<T: PersistentModel>(_ model: T) -> T {
        context.insert(model)
        return model
    }

    private func fetchTask(id: UUID) throws -> TaskModel? {
        let identifier = id
        return try context.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == identifier })).first
    }

    private func fetchBlock(id: UUID) throws -> BlockModel? {
        let identifier = id
        return try context.fetch(FetchDescriptor<BlockModel>(predicate: #Predicate { $0.id == identifier })).first
    }

    private func fetchSession(id: UUID) throws -> SessionModel? {
        let identifier = id
        return try context.fetch(FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == identifier })).first
    }

    private func fetchDayPlan(_ day: PlanDay) throws -> DayPlanModel? {
        let y = day.year, m = day.month, d = day.day
        return try context.fetch(FetchDescriptor<DayPlanModel>(predicate: #Predicate {
            $0.year == y && $0.month == m && $0.day == d
        })).first
    }

    private func fetchRoutine(id: UUID) throws -> RoutineModel? {
        let identifier = id
        return try context.fetch(FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == identifier })).first
    }
}
