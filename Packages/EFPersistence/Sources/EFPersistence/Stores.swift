import Foundation
import SwiftData

public enum ExecFnAppGroup {
    public static let identifier = "group.com.execfn.shared"
}

public struct OpenedStores: Sendable {
    public let main: ModelContainer
    public let activity: ModelContainer
    public let directory: URL
    public let usedAppGroup: Bool
    public let mainCloudKit: String
    public let activityCloudKit: String
}

public enum ExecFnStoreFactory {
    public static func make() throws -> OpenedStores {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ExecFnAppGroup.identifier
        ) {
            return try make(in: container, usedAppGroup: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ExecFn", directoryHint: .isDirectory)
        return try make(in: support, usedAppGroup: false)
    }

    public static func make(in directory: URL, usedAppGroup: Bool = false) throws -> OpenedStores {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mainSchema = Schema(versionedSchema: ExecFnSchemaLatest.self)
        let activitySchema = Schema(versionedSchema: ActivitySchemaV1.self)
        let mainConfiguration = ModelConfiguration(
            "Main",
            schema: mainSchema,
            url: directory.appending(path: "Main.store"),
            cloudKitDatabase: .none
        )
        let activityConfiguration = ModelConfiguration(
            "Activity",
            schema: activitySchema,
            url: directory.appending(path: "Activity.store"),
            cloudKitDatabase: .none
        )
        let main = try ModelContainer(
            for: mainSchema,
            migrationPlan: ExecFnMigrationPlan.self,
            configurations: [mainConfiguration]
        )
        let activity = try ModelContainer(
            for: activitySchema,
            migrationPlan: ActivityMigrationPlan.self,
            configurations: [activityConfiguration]
        )
        return OpenedStores(
            main: main,
            activity: activity,
            directory: directory,
            usedAppGroup: usedAppGroup,
            mainCloudKit: String(describing: mainConfiguration.cloudKitDatabase),
            activityCloudKit: String(describing: activityConfiguration.cloudKitDatabase)
        )
    }
}
