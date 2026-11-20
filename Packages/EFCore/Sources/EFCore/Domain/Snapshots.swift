import Foundation

public enum TaskStatus: String, Codable, Sendable, Hashable {
    case open, done, dropped
}

public enum DropReason: String, Codable, Sendable, Hashable {
    case user, routineExpired
}

public enum TaskEnergy: String, Codable, Sendable, Hashable {
    case low, high
}

public enum DayEnergy: String, Codable, Sendable, Hashable {
    case low, normal, high
}

public enum DayMode: String, Codable, Sendable, Hashable {
    case ideal, minimum, pause
}

public struct EventRef: Hashable, Codable, Sendable {
    public var externalID: String
    public var occurrenceStart: Date

    public init(externalID: String, occurrenceStart: Date) {
        self.externalID = externalID
        self.occurrenceStart = occurrenceStart
    }
}

public enum Cue: Hashable, Codable, Sendable {
    case atTime(Date)
    case afterEvent(EventRef)
    case onMacWake
    case focusChanged(String)
}

public struct IfThenPlan: Hashable, Codable, Sendable {
    public var text: String
    public var cue: Cue?

    public init(text: String, cue: Cue? = nil) {
        self.text = text
        self.cue = cue
    }
}

public struct TaskSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var firstStep: String?
    public var notes: String?
    public var bucketID: UUID?
    public var status: TaskStatus
    public var dropReason: DropReason?
    public var estimateMinutes: Int?
    public var energy: TaskEnergy?
    public var dueDate: Date?
    public var ifThen: IfThenPlan?
    public var isTodayMust: Bool
    public var todayOrder: Int?
    public var isMinimum: Bool
    public var isSomeday: Bool
    public var carriedFrom: PlanDay?
    public var rolloverCount: Int
    public var routineID: UUID?
    public var routineDay: PlanDay?
    public var createdAt: Date
    public var completedAt: Date?
    public var lastTouchedAt: Date

    public init(
        id: UUID,
        title: String,
        firstStep: String? = nil,
        notes: String? = nil,
        bucketID: UUID? = nil,
        status: TaskStatus = .open,
        dropReason: DropReason? = nil,
        estimateMinutes: Int? = nil,
        energy: TaskEnergy? = nil,
        dueDate: Date? = nil,
        ifThen: IfThenPlan? = nil,
        isTodayMust: Bool = false,
        todayOrder: Int? = nil,
        isMinimum: Bool = false,
        isSomeday: Bool = false,
        carriedFrom: PlanDay? = nil,
        rolloverCount: Int = 0,
        routineID: UUID? = nil,
        routineDay: PlanDay? = nil,
        createdAt: Date,
        completedAt: Date? = nil,
        lastTouchedAt: Date
    ) {
        self.id = id
        self.title = title
        self.firstStep = firstStep
        self.notes = notes
        self.bucketID = bucketID
        self.status = status
        self.dropReason = dropReason
        self.estimateMinutes = estimateMinutes
        self.energy = energy
        self.dueDate = dueDate
        self.ifThen = ifThen
        self.isTodayMust = isTodayMust
        self.todayOrder = todayOrder
        self.isMinimum = isMinimum
        self.isSomeday = isSomeday
        self.carriedFrom = carriedFrom
        self.rolloverCount = rolloverCount
        self.routineID = routineID
        self.routineDay = routineDay
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastTouchedAt = lastTouchedAt
    }
}

public enum BlockResolution: String, Codable, Sendable, Hashable {
    case rescheduled, unscheduled, didIt
}

public struct BlockSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var start: Date
    public var end: Date
    public var resolution: BlockResolution?

    public init(id: UUID, taskID: UUID, start: Date, end: Date, resolution: BlockResolution? = nil) {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
        self.resolution = resolution
    }
}

public enum SessionKind: String, Codable, Sendable, Hashable {
    case timed, unverified
}

public enum SessionEnd: String, Codable, Sendable, Hashable {
    case user, autoEnded, appQuit
}

public struct SessionSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var start: Date
    public var end: Date?
    public var kind: SessionKind
    public var endedBy: SessionEnd?

    public var isEstimatorEligible: Bool {
        kind == .timed && endedBy == .user && end != nil
    }

    public init(
        id: UUID,
        taskID: UUID,
        start: Date,
        end: Date? = nil,
        kind: SessionKind,
        endedBy: SessionEnd? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
        self.kind = kind
        self.endedBy = endedBy
    }
}

public enum RoutineSchedule: Hashable, Codable, Sendable {
    case daily
    case weekdays
    case weekly(Set<Int>)
    case everyNDays(Int, anchor: PlanDay)
}

public struct RoutineTemplate: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var schedule: RoutineSchedule
    public var timeOfDayMinutes: Int?
    public var estimateMinutes: Int?
    public var checklist: [String]
    public var bucketID: UUID?
    public var energy: TaskEnergy?
    public var isActive: Bool

    public init(
        id: UUID,
        title: String,
        schedule: RoutineSchedule,
        timeOfDayMinutes: Int? = nil,
        estimateMinutes: Int? = nil,
        checklist: [String] = [],
        bucketID: UUID? = nil,
        energy: TaskEnergy? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.timeOfDayMinutes = timeOfDayMinutes
        self.estimateMinutes = estimateMinutes
        self.checklist = checklist
        self.bucketID = bucketID
        self.energy = energy
        self.isActive = isActive
    }
}

public struct DayPlanSnapshot: Hashable, Sendable {
    public var day: PlanDay
    public var mode: DayMode
    public var energy: DayEnergy?

    public init(day: PlanDay, mode: DayMode = .ideal, energy: DayEnergy? = nil) {
        self.day = day
        self.mode = mode
        self.energy = energy
    }
}

public enum EventAvailability: String, Sendable, Hashable, Codable {
    case busy, free, tentative, unavailable, notSupported
}

public struct EventSnapshot: Hashable, Sendable {
    public var ref: EventRef
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var availability: EventAvailability
    public var hasLocation: Bool

    public init(
        ref: EventRef,
        calendarID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        availability: EventAvailability,
        hasLocation: Bool
    ) {
        self.ref = ref
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.availability = availability
        self.hasLocation = hasLocation
    }
}

public struct EventAnnotation: Hashable, Codable, Sendable {
    public var ref: EventRef
    public var travelMinutes: Int?
    public var transitionAlerts: Bool

    public init(ref: EventRef, travelMinutes: Int? = nil, transitionAlerts: Bool = false) {
        self.ref = ref
        self.travelMinutes = travelMinutes
        self.transitionAlerts = transitionAlerts
    }
}

public struct BucketSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var order: Int
    public var focusFilterID: String?

    public init(
        id: UUID,
        name: String,
        colorHex: String = "#8E8E93",
        order: Int = 0,
        focusFilterID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.focusFilterID = focusFilterID
    }
}

public struct SubtaskSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var title: String
    public var order: Int
    public var isDone: Bool

    public init(id: UUID, taskID: UUID, title: String, order: Int = 0, isDone: Bool = false) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.order = order
        self.isDone = isDone
    }
}

public enum ActivityKind: String, Codable, Sendable, Hashable {
    case taskCreated
    case taskEdited
    case taskCompleted
    case taskDropped
    case mustSet
    case mustCleared
    case carriedTriaged
    case rolloverRan
    case sessionStarted
    case sessionEnded
    case checkInShown
    case checkInAnswered
    case blockCreated
    case blockResolved
    case notificationPlanned
    case notificationActed
    case cueFired
    case freshStart
    case freshStartUndone
    case comebackShown
    case dayModeSet
    case energyCheckIn
    case presence
    case calendarAccessChanged
}

public struct ActivityEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var at: Date
    public var kind: ActivityKind
    public var taskID: UUID?
    public var payload: [String: String]

    public init(
        id: UUID = UUID(),
        at: Date,
        kind: ActivityKind,
        taskID: UUID? = nil,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.taskID = taskID
        self.payload = payload
    }
}
