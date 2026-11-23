import Foundation
import SwiftData

/// v2 (Phase 2): `SessionModel.startModeRaw`, `SessionModel.checkInAnchor`, `DayPlanModel.rolledOverAt`.
enum ExecFnSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            TaskModel.self,
            BlockModel.self,
            SessionModel.self,
            SubtaskModel.self,
            BucketModel.self,
            RoutineModel.self,
            DayPlanModel.self,
            EventAnnotationModel.self,
        ]
    }
}

/// The latest main-store schema. Stores.swift opens this.
typealias ExecFnSchemaLatest = ExecFnSchemaV2

enum ExecFnMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ExecFnSchemaV1.self, ExecFnSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ExecFnSchemaV1.self, toVersion: ExecFnSchemaV2.self)]
    }
}

enum ActivitySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ActivityEventModel.self]
    }
}

enum ActivityMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ActivitySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
