import EFCore
import Foundation
import SwiftData
import Testing
@testable import EFPersistence

@MainActor
struct PhaseTwoPersistenceTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ExecFn-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A store written by Phase 1 (schema v1) opens under v2 with its data intact.
    @Test func v1StoreMigratesToV2() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "Main.store")
        let taskID = UUID(), sessionID = UUID()
        do {
            let v1 = Schema(versionedSchema: ExecFnSchemaV1.self)
            let container = try ModelContainer(
                for: v1,
                configurations: [ModelConfiguration("Main", schema: v1, url: url, cloudKitDatabase: .none)]
            )
            let ctx = ModelContext(container)
            let task = ExecFnSchemaV1.TaskModel()
            task.id = taskID
            task.title = "From Phase 1"
            ctx.insert(task)
            let session = ExecFnSchemaV1.SessionModel()
            session.id = sessionID
            session.taskID = taskID
            ctx.insert(session)
            let plan = ExecFnSchemaV1.DayPlanModel()
            plan.year = 2026; plan.month = 11; plan.day = 19
            ctx.insert(plan)
            try ctx.save()
        }
        let opened = try ExecFnStoreFactory.make(in: dir)
        let repo = TaskRepository(container: opened.main)
        #expect(try repo.task(id: taskID)?.title == "From Phase 1")
        let session = try repo.session(id: sessionID)
        #expect(session?.startMode == .standard)
        #expect(session?.checkInAnchor == nil)
        #expect(try repo.lastRolloverDay() == nil)
    }

    @Test func rolloverWritesChangesAndMarkerOnceAndIsIdempotent() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let opened = try ExecFnStoreFactory.make(in: dir)
        let repo = TaskRepository(container: opened.main)
        let now = Date(timeIntervalSince1970: 1_763_640_000)
        var must = TaskSnapshot(id: UUID(), title: "Invoice", createdAt: now, lastTouchedAt: now)
        must.isTodayMust = true
        must.todayOrder = 0
        try repo.upsert(must)

        let d19 = PlanDay(year: 2026, month: 11, day: 19), d20 = PlanDay(year: 2026, month: 11, day: 20)
        #expect(try repo.rollOverIfNeeded(today: d19, now: now) != nil)       // first run seeds the marker
        let carriedOn19 = try #require(try repo.task(id: must.id))
        #expect(carriedOn19.carriedFrom == d19.advanced(by: -1))
        #expect(try repo.lastRolloverDay() == d19)

        #expect(try repo.rollOverIfNeeded(today: d19, now: now) == nil)       // same day: no-op
        #expect(try repo.task(id: must.id)?.rolloverCount == 1)

        let next = try #require(try repo.rollOverIfNeeded(today: d20, now: now + 86400))
        #expect(next.summary.clearedCarried == 1)
        #expect(try repo.task(id: must.id)?.carriedFrom == nil)
        #expect(try repo.lastRolloverDay() == d20)

        // A second context on the same container sees the marker (it's in the store, not memory).
        let fresh = TaskRepository(context: ModelContext(opened.main))
        #expect(try fresh.lastRolloverDay() == d20)
    }

    @Test func repositoryUsesTheMainContext() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let opened = try ExecFnStoreFactory.make(in: dir)
        let repo = TaskRepository(container: opened.main)
        #expect(repo.context === opened.main.mainContext)
    }

    @Test func workingSetHasOpenAndRecentlyDone() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = TaskRepository(container: try ExecFnStoreFactory.make(in: dir).main)
        let now = Date(timeIntervalSince1970: 1_763_640_000)
        let open = TaskSnapshot(id: UUID(), title: "Open", createdAt: now, lastTouchedAt: now)
        let doneToday = TaskCommands.complete(TaskSnapshot(id: UUID(), title: "Today", createdAt: now, lastTouchedAt: now), now: now)
        let doneOld = TaskCommands.complete(TaskSnapshot(id: UUID(), title: "Old", createdAt: now, lastTouchedAt: now), now: now - 3 * 86400)
        let dropped = TaskCommands.drop(TaskSnapshot(id: UUID(), title: "Dropped", createdAt: now, lastTouchedAt: now), now: now)
        try repo.save(tasks: [open, doneToday, doneOld, dropped])
        let set = Set(try repo.workingSet(since: now - 3600).map(\.title))
        #expect(set == ["Open", "Today"])
    }

    @Test func sessionsRoundTripWithStartMode() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = TaskRepository(container: try ExecFnStoreFactory.make(in: dir).main)
        let now = Date(timeIntervalSince1970: 1_763_640_000)
        var s = SessionRules.start(taskID: UUID(), mode: .fiveMinutes, now: now)
        try repo.save(sessions: [s])
        #expect(try repo.openSessions() == [s])
        s = SessionRules.answer(s, .keepGoing, now: now + 300)
        try repo.save(sessions: [s])
        #expect(try repo.session(id: s.id) == s)
        s = SessionRules.answer(s, .stop, now: now + 900)
        try repo.save(sessions: [s])
        #expect(try repo.openSessions().isEmpty)
    }

    @Test func pinStoreRoundTrips() throws {
        let suite = "execfn-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pins = PinStore(defaults: defaults)
        #expect(pins.pinnedTaskID == nil)
        let id = UUID()
        pins.pin(id)
        #expect(PinStore(defaults: defaults).pinnedTaskID == id)
        pins.clear()
        #expect(pins.pinnedTaskID == nil)
    }

    @Test func rolloverSpawnsADueRoutineOnce() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = TaskRepository(container: try ExecFnStoreFactory.make(in: dir).main)
        let now = Date(timeIntervalSince1970: 1_763_640_000)
        let template = RoutineTemplate(id: UUID(), title: "Dishes", schedule: .daily, checklist: ["Rinse"], isActive: true)
        try repo.upsert(template)
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let first = try #require(try repo.rollOverIfNeeded(today: day, now: now))
        #expect(first.spawnedTasks.map(\.title) == ["Dishes"])
        #expect(try repo.allSubtasks().map(\.title) == ["Rinse"])
        #expect(try repo.rollOverIfNeeded(today: day, now: now) == nil)
        let dishes = try repo.allTasks().filter { $0.routineID == template.id }
        #expect(dishes.count == 1)
    }
}
