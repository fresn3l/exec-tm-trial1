import Foundation
import SwiftData

@Model
final class TaskModel {
    var id: UUID = UUID()
    var title: String = ""
    var firstStep: String?
    var notes: String?
    var bucketID: UUID?
    var statusRaw: String = "open"
    var dropReasonRaw: String?
    var estimateMinutes: Int?
    var energyRaw: String?
    var dueDate: Date?
    var ifThenJSON: Data?
    var isTodayMust: Bool = false
    var todayOrder: Int?
    var isMinimum: Bool = false
    var isSomeday: Bool = false
    var carriedYear: Int?
    var carriedMonth: Int?
    var carriedDay: Int?
    var rolloverCount: Int = 0
    var routineID: UUID?
    var routineYear: Int?
    var routineMonth: Int?
    var routineDay: Int?
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var completedAt: Date?
    var lastTouchedAt: Date = Date(timeIntervalSince1970: 0)

    @Relationship(deleteRule: .cascade, inverse: \BlockModel.task)
    var blocks: [BlockModel]? = nil

    @Relationship(deleteRule: .cascade, inverse: \SessionModel.task)
    var sessions: [SessionModel]? = nil

    @Relationship(deleteRule: .cascade, inverse: \SubtaskModel.task)
    var subtasks: [SubtaskModel]? = nil

    init() {}
}

@Model
final class BlockModel {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var start: Date = Date(timeIntervalSince1970: 0)
    var end: Date = Date(timeIntervalSince1970: 0)
    var resolutionRaw: String?
    var task: TaskModel? = nil

    init() {}
}

@Model
final class SessionModel {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var start: Date = Date(timeIntervalSince1970: 0)
    var end: Date?
    var kindRaw: String = "timed"
    var endedByRaw: String?
    var task: TaskModel? = nil

    init() {}
}

@Model
final class SubtaskModel {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var title: String = ""
    var sortIndex: Int = 0
    var isDone: Bool = false
    var task: TaskModel? = nil

    init() {}
}

@Model
final class BucketModel {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var sortIndex: Int = 0
    var focusFilterID: String?

    init() {}
}

@Model
final class RoutineModel {
    var id: UUID = UUID()
    var title: String = ""
    var scheduleJSON: Data = Data()
    var timeOfDayMinutes: Int?
    var estimateMinutes: Int?
    var checklistJSON: Data = Data()
    var bucketID: UUID?
    var energyRaw: String?
    var isActive: Bool = true

    init() {}
}

@Model
final class DayPlanModel {
    var year: Int = 1970
    var month: Int = 1
    var day: Int = 1
    var modeRaw: String = "ideal"
    var energyRaw: String?

    init() {}
}

@Model
final class EventAnnotationModel {
    var externalID: String = ""
    var occurrenceStart: Date = Date(timeIntervalSince1970: 0)
    var travelMinutes: Int?
    var transitionAlerts: Bool = false

    init() {}
}

@Model
final class ActivityEventModel {
    var id: UUID = UUID()
    var at: Date = Date(timeIntervalSince1970: 0)
    var kindRaw: String = "presence"
    var taskID: UUID?
    var payload: Data?

    init() {}
}
