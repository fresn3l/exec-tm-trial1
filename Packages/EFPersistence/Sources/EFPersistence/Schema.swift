import Foundation
import SwiftData

enum ExecFnSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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

enum ExecFnMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ExecFnSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
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
