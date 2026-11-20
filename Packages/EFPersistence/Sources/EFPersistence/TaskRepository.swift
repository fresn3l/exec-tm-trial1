import EFCore
import Foundation
import SwiftData

@MainActor
public final class TaskRepository {
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.context = ModelContext(container)
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

    private func fetchRoutine(id: UUID) throws -> RoutineModel? {
        let identifier = id
        return try context.fetch(FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == identifier })).first
    }
}
