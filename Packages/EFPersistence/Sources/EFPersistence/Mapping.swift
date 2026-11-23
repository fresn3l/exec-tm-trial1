import EFCore
import Foundation

enum SnapshotMapper {
    static func apply(_ snapshot: TaskSnapshot, to model: TaskModel) throws {
        model.id = snapshot.id
        model.title = snapshot.title
        model.firstStep = snapshot.firstStep
        model.notes = snapshot.notes
        model.bucketID = snapshot.bucketID
        model.statusRaw = snapshot.status.rawValue
        model.dropReasonRaw = snapshot.dropReason?.rawValue
        model.estimateMinutes = snapshot.estimateMinutes
        model.energyRaw = snapshot.energy?.rawValue
        model.dueDate = snapshot.dueDate
        model.ifThenJSON = try snapshot.ifThen.map(JSONCoders.encode)
        model.isTodayMust = snapshot.isTodayMust
        model.todayOrder = snapshot.todayOrder
        model.isMinimum = snapshot.isMinimum
        model.isSomeday = snapshot.isSomeday
        model.carriedYear = snapshot.carriedFrom?.year
        model.carriedMonth = snapshot.carriedFrom?.month
        model.carriedDay = snapshot.carriedFrom?.day
        model.rolloverCount = snapshot.rolloverCount
        model.routineID = snapshot.routineID
        model.routineYear = snapshot.routineDay?.year
        model.routineMonth = snapshot.routineDay?.month
        model.routineDay = snapshot.routineDay?.day
        model.createdAt = snapshot.createdAt
        model.completedAt = snapshot.completedAt
        model.lastTouchedAt = snapshot.lastTouchedAt
    }

    static func task(from model: TaskModel) throws -> TaskSnapshot {
        TaskSnapshot(
            id: model.id,
            title: model.title,
            firstStep: model.firstStep,
            notes: model.notes,
            bucketID: model.bucketID,
            status: TaskStatus(rawValue: model.statusRaw) ?? .open,
            dropReason: model.dropReasonRaw.flatMap(DropReason.init(rawValue:)),
            estimateMinutes: model.estimateMinutes,
            energy: model.energyRaw.flatMap(TaskEnergy.init(rawValue:)),
            dueDate: model.dueDate,
            ifThen: try json(IfThenPlan.self, from: model.ifThenJSON, field: "ifThen"),
            isTodayMust: model.isTodayMust,
            todayOrder: model.todayOrder,
            isMinimum: model.isMinimum,
            isSomeday: model.isSomeday,
            carriedFrom: planDay(year: model.carriedYear, month: model.carriedMonth, day: model.carriedDay),
            rolloverCount: model.rolloverCount,
            routineID: model.routineID,
            routineDay: planDay(year: model.routineYear, month: model.routineMonth, day: model.routineDay),
            createdAt: model.createdAt,
            completedAt: model.completedAt,
            lastTouchedAt: model.lastTouchedAt
        )
    }

    static func apply(_ snapshot: BlockSnapshot, to model: BlockModel) {
        model.id = snapshot.id
        model.taskID = snapshot.taskID
        model.start = snapshot.start
        model.end = snapshot.end
        model.resolutionRaw = snapshot.resolution?.rawValue
    }

    static func block(from model: BlockModel) -> BlockSnapshot {
        BlockSnapshot(
            id: model.id,
            taskID: model.taskID,
            start: model.start,
            end: model.end,
            resolution: model.resolutionRaw.flatMap(BlockResolution.init(rawValue:))
        )
    }

    static func apply(_ snapshot: SessionSnapshot, to model: SessionModel) {
        model.id = snapshot.id
        model.taskID = snapshot.taskID
        model.start = snapshot.start
        model.end = snapshot.end
        model.kindRaw = snapshot.kind.rawValue
        model.endedByRaw = snapshot.endedBy?.rawValue
        model.startModeRaw = snapshot.startMode.rawValue
        model.checkInAnchor = snapshot.checkInAnchor
    }

    static func session(from model: SessionModel) -> SessionSnapshot {
        SessionSnapshot(
            id: model.id,
            taskID: model.taskID,
            start: model.start,
            end: model.end,
            kind: SessionKind(rawValue: model.kindRaw) ?? .timed,
            endedBy: model.endedByRaw.flatMap(SessionEnd.init(rawValue:)),
            startMode: SessionStartMode(rawValue: model.startModeRaw) ?? .standard,
            checkInAnchor: model.checkInAnchor
        )
    }

    static func apply(_ snapshot: SubtaskSnapshot, to model: SubtaskModel) {
        model.id = snapshot.id
        model.taskID = snapshot.taskID
        model.title = snapshot.title
        model.sortIndex = snapshot.order
        model.isDone = snapshot.isDone
    }

    static func subtask(from model: SubtaskModel) -> SubtaskSnapshot {
        SubtaskSnapshot(
            id: model.id,
            taskID: model.taskID,
            title: model.title,
            order: model.sortIndex,
            isDone: model.isDone
        )
    }

    static func apply(_ snapshot: BucketSnapshot, to model: BucketModel) {
        model.id = snapshot.id
        model.name = snapshot.name
        model.colorHex = snapshot.colorHex
        model.sortIndex = snapshot.order
        model.focusFilterID = snapshot.focusFilterID
    }

    static func bucket(from model: BucketModel) -> BucketSnapshot {
        BucketSnapshot(
            id: model.id,
            name: model.name,
            colorHex: model.colorHex,
            order: model.sortIndex,
            focusFilterID: model.focusFilterID
        )
    }

    static func apply(_ snapshot: RoutineTemplate, to model: RoutineModel) throws {
        model.id = snapshot.id
        model.title = snapshot.title
        model.scheduleJSON = try JSONCoders.encode(snapshot.schedule)
        model.timeOfDayMinutes = snapshot.timeOfDayMinutes
        model.estimateMinutes = snapshot.estimateMinutes
        model.checklistJSON = try JSONCoders.encode(snapshot.checklist)
        model.bucketID = snapshot.bucketID
        model.energyRaw = snapshot.energy?.rawValue
        model.isActive = snapshot.isActive
    }

    static func routine(from model: RoutineModel) throws -> RoutineTemplate {
        guard let schedule = try json(RoutineSchedule.self, from: model.scheduleJSON, field: "schedule") else {
            throw MappingError.corrupt("schedule")
        }
        let checklist = try json([String].self, from: model.checklistJSON, field: "checklist") ?? []
        return RoutineTemplate(
            id: model.id,
            title: model.title,
            schedule: schedule,
            timeOfDayMinutes: model.timeOfDayMinutes,
            estimateMinutes: model.estimateMinutes,
            checklist: checklist,
            bucketID: model.bucketID,
            energy: model.energyRaw.flatMap(TaskEnergy.init(rawValue:)),
            isActive: model.isActive
        )
    }

    static func apply(_ snapshot: DayPlanSnapshot, to model: DayPlanModel) {
        model.year = snapshot.day.year
        model.month = snapshot.day.month
        model.day = snapshot.day.day
        model.modeRaw = snapshot.mode.rawValue
        model.energyRaw = snapshot.energy?.rawValue
    }

    static func dayPlan(from model: DayPlanModel) -> DayPlanSnapshot {
        DayPlanSnapshot(
            day: PlanDay(year: model.year, month: model.month, day: model.day),
            mode: DayMode(rawValue: model.modeRaw) ?? .ideal,
            energy: model.energyRaw.flatMap(DayEnergy.init(rawValue:))
        )
    }

    static func apply(_ snapshot: EventAnnotation, to model: EventAnnotationModel) {
        model.externalID = snapshot.ref.externalID
        model.occurrenceStart = snapshot.ref.occurrenceStart
        model.travelMinutes = snapshot.travelMinutes
        model.transitionAlerts = snapshot.transitionAlerts
    }

    static func annotation(from model: EventAnnotationModel) -> EventAnnotation {
        EventAnnotation(
            ref: EventRef(externalID: model.externalID, occurrenceStart: model.occurrenceStart),
            travelMinutes: model.travelMinutes,
            transitionAlerts: model.transitionAlerts
        )
    }

    private static func planDay(year: Int?, month: Int?, day: Int?) -> PlanDay? {
        guard let year, let month, let day else { return nil }
        return PlanDay(year: year, month: month, day: day)
    }

    private static func json<T: Decodable>(_ type: T.Type, from data: Data?, field: String) throws -> T? {
        guard let data, !data.isEmpty else { return nil }
        do {
            return try JSONCoders.decode(type, from: data)
        } catch {
            throw MappingError.corrupt(field)
        }
    }
}
