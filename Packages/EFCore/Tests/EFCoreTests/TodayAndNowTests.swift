import Foundation
import Testing
@testable import EFCore

struct TodayTests {
    @Test func inboxExcludesCarriedMustsSomedayRoutinesBucketsAndBlocks() {
        let plain = Fx.task("Plain")
        let carried = Fx.task("Carried", carried: Fx.day(19))
        let must = Fx.task("Must", must: true)
        let someday = Fx.task("Someday", someday: true)
        let routine = Fx.task("Meds", routine: (UUID(), Fx.day(20)))
        let bucketed = Fx.task("Bucketed", bucket: UUID())
        let blocked = Fx.task("Blocked")
        let done = Fx.task("Done", status: .done)
        let block = BlockSnapshot(id: UUID(), taskID: blocked.id, start: Fx.t0, end: Fx.t0 + 1800)
        let inbox = TodayRules.inbox(
            tasks: [plain, carried, must, someday, routine, bucketed, blocked, done],
            blocks: [block]
        )
        #expect(inbox.map(\.id) == [plain.id])
    }

    @Test func laterMovesACarriedTaskIntoTheInbox() {
        let carried = Fx.task("Carried", carried: Fx.day(19))
        let later = TaskCommands.triage(carried, .later, among: [carried], now: Fx.t0)
        #expect(TodayRules.carriedRow(tasks: [later]).isEmpty)
        #expect(TodayRules.inbox(tasks: [later]).count == 1)
    }

    @Test func carriedRowShowsThreeThenMore() {
        let items = (0..<5).map { Fx.task("C\($0)", carried: Fx.day(19), created: Fx.t0 + Double($0)) }
        let row = TodayRules.carriedRow(tasks: items)
        #expect(row.visible.map(\.title) == ["C0", "C1", "C2"])
        #expect(row.moreCount == 2)
        #expect(TodayRules.carriedRow(tasks: items, dayMode: .pause).isEmpty)
    }

    @Test func capSuggestsASwapAtThreeButAllowsMore() {
        let musts = (0..<3).map { Fx.task("M\($0)", must: true, order: $0) }
        #expect(TodayRules.checkAddingMust(tasks: Array(musts.prefix(2)), settings: .standard) == .ok)
        #expect(TodayRules.checkAddingMust(tasks: musts, settings: .standard) == .overCap(current: 3, cap: 3))
        let extra = TaskCommands.makeMust(Fx.task("Fourth"), among: musts, now: Fx.t0)
        #expect(extra.todayOrder == 3)
        #expect(TodayRules.musts(tasks: musts + [extra]).count == 4)
    }

    @Test func triageTodayClearsCarriedAndAppends() {
        let must = Fx.task("Must", must: true, order: 0)
        let carried = Fx.task("Carried", carried: Fx.day(19))
        let t = TaskCommands.triage(carried, .today, among: [must, carried], now: Fx.t0)
        #expect(t.isTodayMust && t.carriedFrom == nil && t.todayOrder == 1)
    }

    @Test func captureNeedsOnlyATitle() {
        #expect(TaskCommands.capture(title: "   ", now: Fx.t0) == nil)
        let t = TaskCommands.capture(title: "  Email Sam  ", now: Fx.t0)
        #expect(t?.title == "Email Sam")
        #expect(t?.status == .open)
    }
}

struct NowRuleTests {
    let settings = PlannerSettings.standard

    @Test func runningSessionBeatsEverything() {
        let pinned = Fx.task("Pinned")
        let working = Fx.task("Working")
        let must = Fx.task("Must", must: true, order: 0)
        let session = SessionRules.start(taskID: working.id, mode: .standard, now: Fx.t0)
        let r = NowRule.evaluate(tasks: [pinned, working, must], sessions: [session], pinnedTaskID: pinned.id, settings: settings, now: Fx.t0)
        #expect(r.now == .init(taskID: working.id, source: .session))
        #expect(r.next == .init(taskID: pinned.id, source: .pinned))
    }

    @Test func pinBeatsBlocksAndMusts() {
        let pinned = Fx.task("Pinned")
        let blockTask = Fx.task("Blocked")
        let must = Fx.task("Must", must: true, order: 0)
        let block = BlockSnapshot(id: UUID(), taskID: blockTask.id, start: Fx.t0 - 60, end: Fx.t0 + 600)
        let r = NowRule.evaluate(tasks: [pinned, blockTask, must], blocks: [block], sessions: [], pinnedTaskID: pinned.id, settings: settings, now: Fx.t0)
        #expect(r.now?.source == .pinned)
        #expect(r.next == .init(taskID: blockTask.id, source: .currentBlock))
    }

    @Test func currentBlockBeatsMust() {
        let blockTask = Fx.task("Blocked")
        let must = Fx.task("Must", must: true, order: 0)
        let block = BlockSnapshot(id: UUID(), taskID: blockTask.id, start: Fx.t0 - 60, end: Fx.t0 + 600)
        let r = NowRule.evaluate(tasks: [blockTask, must], blocks: [block], sessions: [], pinnedTaskID: nil, settings: settings, now: Fx.t0)
        #expect(r.now?.source == .currentBlock)
        #expect(r.next?.taskID == must.id)
    }

    @Test func firstMustByOrder() {
        let second = Fx.task("Second", must: true, order: 1, created: Fx.t0 - 100)
        let first = Fx.task("First", must: true, order: 0)
        let r = NowRule.evaluate(tasks: [second, first], sessions: [], pinnedTaskID: nil, settings: settings, now: Fx.t0)
        #expect(r.now == .init(taskID: first.id, source: .must))
        #expect(r.next == .init(taskID: second.id, source: .must))
    }

    @Test func upcomingBlockOnlyWithinLookahead() {
        let soon = Fx.task("Soon")
        let later = Fx.task("Later")
        let blocks = [
            BlockSnapshot(id: UUID(), taskID: soon.id, start: Fx.t0 + 30 * 60, end: Fx.t0 + 60 * 60),
            BlockSnapshot(id: UUID(), taskID: later.id, start: Fx.t0 + 90 * 60, end: Fx.t0 + 120 * 60),
        ]
        let r = NowRule.evaluate(tasks: [soon, later], blocks: blocks, sessions: [], pinnedTaskID: nil, settings: settings, now: Fx.t0)
        #expect(r.now == .init(taskID: soon.id, source: .upcomingBlock))
        #expect(r.next == nil)
    }

    @Test func emptyStateOffersMustsThenDueThenOldest() {
        let old = Fx.task("Old", created: Fx.t0 - 9000)
        let newer = Fx.task("Newer", created: Fx.t0 - 10)
        let due = Fx.task("Due", created: Fx.t0, due: Fx.t0 + 86400)
        let someday = Fx.task("Someday", created: Fx.t0 - 99999, someday: true)
        let r = NowRule.evaluate(tasks: [old, newer, due, someday], sessions: [], pinnedTaskID: nil, settings: settings, now: Fx.t0)
        #expect(r.now == nil)
        #expect(r.candidates == [due.id, old.id, newer.id])
    }

    @Test func stalePinIsIgnoredAndFlagged() {
        let done = Fx.task("Done", status: .done)
        let must = Fx.task("Must", must: true, order: 0)
        let r = NowRule.evaluate(tasks: [done, must], sessions: [], pinnedTaskID: done.id, settings: settings, now: Fx.t0)
        #expect(r.now?.taskID == must.id)
        #expect(r.pinIsStale)
    }

    @Test func emptyEverything() {
        let r = NowRule.evaluate(tasks: [], sessions: [], pinnedTaskID: nil, settings: settings, now: Fx.t0)
        #expect(r.now == nil && r.next == nil && r.candidates.isEmpty && !r.pinIsStale)
    }
}
