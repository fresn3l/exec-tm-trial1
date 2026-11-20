import EFCore
import Foundation
import SwiftData
import Testing
@testable import EFPersistence

@MainActor
struct PersistenceTests {
    @Test func mapperRoundTripAndStoreStaySeparate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ExecFn-\(UUID().uuidString)", directoryHint: .isDirectory)
        let opened = try ExecFnStoreFactory.make(in: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(opened.mainCloudKit.localizedCaseInsensitiveContains("none"))
        #expect(opened.activityCloudKit.localizedCaseInsensitiveContains("none"))
        #expect(opened.main.schema.entities.contains { $0.name.contains("ActivityEvent") } == false)
        #expect(opened.activity.schema.entities.contains { $0.name.contains("ActivityEvent") })

        let repository = TaskRepository(container: opened.main)
        let when = Date(timeIntervalSince1970: 1_763_640_000)
        let task = TaskSnapshot(
            id: UUID(),
            title: "Send the invoice",
            firstStep: "Open the April PDF",
            notes: "Account 14",
            status: .open,
            estimateMinutes: 25,
            energy: .low,
            ifThen: IfThenPlan(text: "When I sit down, I open the PDF", cue: .onMacWake),
            isTodayMust: true,
            todayOrder: 0,
            carriedFrom: PlanDay(year: 2026, month: 11, day: 19),
            createdAt: when,
            lastTouchedAt: when
        )
        try repository.upsert(task)
        let loaded = try repository.task(id: task.id)
        #expect(loaded == task)

        let block = BlockSnapshot(
            id: UUID(),
            taskID: task.id,
            start: when,
            end: when.addingTimeInterval(1800)
        )
        try repository.upsert(block)
        #expect(try repository.block(id: block.id) == block)

        let session = SessionSnapshot(
            id: UUID(),
            taskID: task.id,
            start: when,
            end: when.addingTimeInterval(600),
            kind: .timed,
            endedBy: .user
        )
        try repository.upsert(session)
        let storedSession = try repository.session(id: session.id)
        #expect(storedSession == session)
        #expect(storedSession?.isEstimatorEligible == true)

        let routine = RoutineTemplate(
            id: UUID(),
            title: "Meds",
            schedule: .weekdays,
            checklist: ["Water", "Pill"]
        )
        try repository.upsert(routine)
        #expect(try repository.routine(id: routine.id) == routine)

        let log = ActivityLog(container: opened.activity)
        let recorded = ActivityEvent(
            at: when,
            kind: .calendarAccessChanged,
            payload: ["state": "full"]
        )
        try log.append(recorded)
        #expect(try log.events() == [recorded])

        let jsonl = try log.exportJSONL()
        #expect(jsonl.contains("calendarAccessChanged"))
        #expect(jsonl.contains("full"))
        let csv = try log.exportCSV()
        #expect(csv.hasPrefix("id,at,kind,taskID,payload"))
        #expect(csv.contains("calendarAccessChanged"))

        let mainContext = ModelContext(opened.main)
        let stray = try mainContext.fetch(FetchDescriptor<TaskModel>())
        #expect(stray.count == 1)
        let activityOnMain = try? mainContext.fetchCount(FetchDescriptor<ActivityEventModel>())
        #expect(activityOnMain == nil || activityOnMain == 0)
    }

    @Test func settingsUseTheSuiteTheyAreGiven() {
        let defaults = UserDefaults(suiteName: "execfn.tests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == .standard)
        var settings = PlannerSettings.standard
        settings.todayCap = 1
        settings.calendarModes = ["work": CalendarModeOverride(mode: .visible, title: "Work")]
        store.save(settings)
        #expect(store.load() == settings)
    }
}
