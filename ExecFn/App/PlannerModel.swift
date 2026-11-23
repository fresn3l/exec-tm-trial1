import AppKit
import EFCore
import EFPersistence
import Observation

/// Tasks, sessions, the pin, and rollover. Every write goes:
/// snapshots → EFCore → repository (one context, D-01) → reload.
@MainActor
@Observable
final class PlannerModel {
    enum CaptureSource: String { case hotkey, app, menuBar }

    private(set) var tasks: [TaskSnapshot] = []
    private(set) var openSession: SessionSnapshot?
    private(set) var pinnedTaskID: UUID?
    /// Ticks every few seconds; drives check-in state and the menu bar label.
    private(set) var now = Date()
    /// Bumped on completion so views can play the D-21 animation.
    private(set) var celebration = 0
    private(set) var lastCelebratedTitle: String?
    var problem: String?

    /// Set when "Add to Today" hits the cap (D-07). The view shows the swap prompt.
    var capPrompt: CapPrompt?
    struct CapPrompt: Identifiable {
        let id = UUID()
        let task: TaskSnapshot
        let current: [TaskSnapshot]
        let cap: Int
        let fromTriage: Bool
    }

    @ObservationIgnored private let repository: TaskRepository?
    @ObservationIgnored private let activity: ActivityLog?
    @ObservationIgnored private let pins: PinStore
    @ObservationIgnored private let settingsProvider: () -> PlannerSettings
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var boundaryTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onSessionChange: ((SessionSnapshot?, TaskSnapshot?) -> Void)?

    init(repository: TaskRepository?, activity: ActivityLog?, pins: PinStore, settings: @escaping () -> PlannerSettings) {
        self.repository = repository
        self.activity = activity
        self.pins = pins
        self.settingsProvider = settings
        self.pinnedTaskID = pins.pinnedTaskID
    }

    var settings: PlannerSettings { settingsProvider() }
    var boundary: DayBoundary { DayBoundary(hour: settings.dayBoundaryHour, timeZone: .current) }
    var today: PlanDay { boundary.planDay(containing: now) }

    // MARK: Derived (D-03, D-06, D-07, D-08)

    var inbox: [TaskSnapshot] { TodayRules.inbox(tasks: tasks) }
    var musts: [TaskSnapshot] { TodayRules.musts(tasks: tasks) }
    var doneToday: [TaskSnapshot] { TodayRules.doneToday(tasks: tasks, today: today, boundary: boundary) }
    var carriedRow: TodayRules.CarriedRow { TodayRules.carriedRow(tasks: tasks) }
    var cap: Int { TodayRules.cap(settings: settings) }

    var nowResult: NowRule.Result {
        NowRule.evaluate(
            tasks: tasks,
            sessions: openSession.map { [$0] } ?? [],
            pinnedTaskID: pinnedTaskID,
            settings: settings,
            now: now
        )
    }

    func task(_ id: UUID?) -> TaskSnapshot? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    var sessionTask: TaskSnapshot? { task(openSession?.taskID) }

    var sessionState: SessionRules.State? {
        guard let s = openSession else { return nil }
        return SessionRules.state(s, estimateMinutes: sessionTask?.estimateMinutes, settings: settings, now: now)
    }

    var isCheckInDue: Bool {
        if case .checkInDue = sessionState { return true }
        return false
    }

    var isFiveMinutePrompt: Bool { openSession.map(SessionRules.isFiveMinutePrompt) ?? false }

    func statusLabel(nextEventStart: Date?) -> StatusLine.Label {
        StatusLine.label(
            session: openSession,
            sessionTask: sessionTask,
            nowTask: task(nowResult.now?.taskID),
            nextEventStart: nextEventStart,
            now: now
        )
    }

    // MARK: Lifecycle

    func start() {
        reload()
        runRolloverIfNeeded(reason: "launch")
        reconcileSession(reason: "launch")
        scheduleBoundaryTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemTimeChanged(reason: "wake") }
        })
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemTimeChanged(reason: "clock") }
            })
        }
    }

    /// D-14: a session still open at quit ends as `appQuit` at quit time.
    func appWillTerminate() {
        guard let s = openSession else { return }
        let ended = SessionRules.end(s, at: Date(), by: .appQuit)
        persist(sessions: [ended])
        log(.sessionEnded, task: s.taskID, ["endedBy": SessionEnd.appQuit.rawValue])
    }

    private func tick() {
        now = Date()
        reconcileSession(reason: "tick")
    }

    private func systemTimeChanged(reason: String) {
        now = Date()
        runRolloverIfNeeded(reason: reason)
        reconcileSession(reason: reason)
        scheduleBoundaryTimer()
    }

    private func scheduleBoundaryTimer() {
        boundaryTimer?.invalidate()
        let fire = Rollover.nextBoundary(after: Date(), boundary: boundary).addingTimeInterval(1)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemTimeChanged(reason: "boundary") }
        }
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    func reload() {
        guard let repository else { return }
        do {
            let since = boundary.start(of: boundary.planDay(containing: Date()))
            tasks = try repository.workingSet(since: since)
            let sessions = try repository.openSessions().sorted { $0.start < $1.start }
            // Only one session runs at a time; older strays end as app-quit.
            if sessions.count > 1 {
                let strays = sessions.dropLast().map { SessionRules.end($0, at: $0.start, by: .appQuit) }
                try repository.save(sessions: Array(strays))
            }
            openSession = sessions.last
            if NowRule.evaluate(tasks: tasks, sessions: [], pinnedTaskID: pinnedTaskID, settings: settings, now: now).pinIsStale {
                setPin(nil)
            }
        } catch {
            problem = String(localized: "Tasks didn't load. Your data is still on disk.")
        }
    }

    private func runRolloverIfNeeded(reason: String) {
        guard let repository else { return }
        do {
            guard let result = try repository.rollOverIfNeeded(today: today, now: Date()) else { return }
            if result.clearPin { setPin(nil) }
            log(.rolloverRan, task: nil, [
                "from": result.summary.from.map(describe) ?? "",
                "to": describe(result.summary.to),
                "carried": String(result.summary.carried),
                "clearedCarried": String(result.summary.clearedCarried),
                "expiredRoutines": String(result.summary.expiredRoutines),
                "trigger": reason,
            ])
            reload()
        } catch {
            problem = String(localized: "The new day didn't start cleanly. Try relaunching ExecFn.")
        }
    }

    /// Evaluated from timestamps, so a slept Mac or a relaunch lands in the same state as a live timer.
    private func reconcileSession(reason: String) {
        guard let s = openSession, case let .shouldAutoEnd(at) = sessionState else { return }
        let ended = SessionRules.end(s, at: at, by: .autoEnded)
        persist(sessions: [ended])
        log(.sessionEnded, task: s.taskID, ["endedBy": SessionEnd.autoEnded.rawValue, "trigger": reason])
        openSession = nil
        onSessionChange?(nil, nil)
    }

    // MARK: Capture & edits

    @discardableResult
    func capture(_ title: String, source: CaptureSource) -> Bool {
        guard let task = TaskCommands.capture(title: title, now: Date()) else { return false }
        persist(tasks: [task])
        log(.taskCreated, task: task.id, ["source": source.rawValue])
        return true
    }

    func edit(_ id: UUID, title: String? = nil, firstStep: String?? = nil, estimateMinutes: Int?? = nil) {
        guard let t = task(id) else { return }
        let edited = TaskCommands.edit(t, title: title, firstStep: firstStep, estimateMinutes: estimateMinutes, now: Date())
        guard edited != t else { return }
        persist(tasks: [edited])
        log(.taskEdited, task: id)
        if openSession?.taskID == id { onSessionChange?(openSession, edited) }
    }

    /// D-07: under the cap → added. At the cap → `capPrompt` is set and nothing changes yet.
    func addToToday(_ id: UUID, fromTriage: Bool = false) {
        guard let t = task(id) else { return }
        switch TodayRules.checkAddingMust(tasks: tasks, settings: settings) {
        case .ok:
            commitMust(t, fromTriage: fromTriage)
        case let .overCap(_, cap):
            capPrompt = CapPrompt(task: t, current: musts, cap: cap, fromTriage: fromTriage)
        }
    }

    func resolveCapPrompt(swapOut: UUID?) {
        guard let prompt = capPrompt else { return }
        capPrompt = nil
        if let swapOut, let out = task(swapOut) {
            persist(tasks: [TaskCommands.clearMust(out, now: Date())])
            log(.mustCleared, task: swapOut, ["reason": "swap"])
        }
        guard let fresh = task(prompt.task.id) else { return }
        commitMust(fresh, fromTriage: prompt.fromTriage, overCap: swapOut == nil)
    }

    private func commitMust(_ t: TaskSnapshot, fromTriage: Bool, overCap: Bool = false) {
        persist(tasks: [TaskCommands.makeMust(t, among: tasks, now: Date())])
        if fromTriage { log(.carriedTriaged, task: t.id, ["action": TaskCommands.Triage.today.rawValue]) }
        log(.mustSet, task: t.id, overCap ? ["overCap": "true"] : [:])
    }

    func removeFromToday(_ id: UUID) {
        guard let t = task(id) else { return }
        persist(tasks: [TaskCommands.clearMust(t, now: Date())])
        log(.mustCleared, task: id)
    }

    func moveMust(from source: IndexSet, to destination: Int) {
        var ordered = musts
        ordered.move(fromOffsets: source, toOffset: destination)
        let renumbered = ordered.enumerated().map { index, t -> TaskSnapshot in
            var copy = t
            copy.todayOrder = index
            return copy
        }
        persist(tasks: renumbered.filter { new in tasks.first { $0.id == new.id }?.todayOrder != new.todayOrder })
    }

    /// D-06 row actions.
    func triage(_ id: UUID, _ action: TaskCommands.Triage) {
        if action == .today { addToToday(id, fromTriage: true); return }
        guard let t = task(id) else { return }
        persist(tasks: [TaskCommands.triage(t, action, among: tasks, now: Date())])
        log(.carriedTriaged, task: id, ["action": action.rawValue])
        if action == .drop { clearPinIfNeeded(id) }
    }

    func keepAllAsLater() {
        let now = Date()
        let changed = carriedRow.all.map { TaskCommands.triage($0, .later, among: tasks, now: now) }
        persist(tasks: changed)
        log(.carriedTriaged, task: nil, ["action": "keepAllLater", "count": String(changed.count)])
    }

    func complete(_ id: UUID) {
        guard let t = task(id) else { return }
        var sessions: [SessionSnapshot] = []
        if let s = openSession, s.taskID == id {
            sessions.append(SessionRules.answer(s, .done, now: Date()))
            log(.sessionEnded, task: id, ["endedBy": SessionEnd.user.rawValue])
        }
        persist(tasks: [TaskCommands.complete(t, now: Date())], sessions: sessions)
        log(.taskCompleted, task: id)
        clearPinIfNeeded(id)
        lastCelebratedTitle = t.title
        celebration += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if !sessions.isEmpty { onSessionChange?(nil, nil) }
    }

    func drop(_ id: UUID) {
        guard let t = task(id) else { return }
        if openSession?.taskID == id { stopSession() }
        persist(tasks: [TaskCommands.drop(t, now: Date())])
        log(.taskDropped, task: id, ["reason": DropReason.user.rawValue])
        clearPinIfNeeded(id)
    }

    // MARK: Pin (D-08)

    func pin(_ id: UUID) {
        setPin(id)
        log(.taskEdited, task: id, ["pinned": "true"])
    }

    func unpin() {
        let old = pinnedTaskID
        setPin(nil)
        log(.taskEdited, task: old, ["pinned": "false"])
    }

    private func clearPinIfNeeded(_ id: UUID) {
        if pinnedTaskID == id { setPin(nil) }
    }

    private func setPin(_ id: UUID?) {
        pinnedTaskID = id
        if let id { pins.pin(id) } else { pins.clear() }
    }

    // MARK: Sessions (D-14, D-27)

    func startSession(_ id: UUID, mode: SessionStartMode) {
        var ended: [SessionSnapshot] = []
        if let current = openSession {
            if current.taskID == id { return }
            ended.append(SessionRules.answer(current, .stop, now: Date()))
            log(.sessionEnded, task: current.taskID, ["endedBy": SessionEnd.user.rawValue, "reason": "switched"])
        }
        let session = SessionRules.start(taskID: id, mode: mode, now: Date())
        persist(sessions: ended + [session])
        log(.sessionStarted, task: id, ["mode": mode.rawValue])
        now = Date()
        onSessionChange?(openSession, task(id))
    }

    func answerCheckIn(_ answer: SessionRules.Answer) {
        guard let s = openSession else { return }
        if answer == .done { complete(s.taskID); log(.checkInAnswered, task: s.taskID, ["answer": "done"]); return }
        let updated = SessionRules.answer(s, answer, now: Date())
        persist(sessions: [updated])
        log(.checkInAnswered, task: s.taskID, [
            "answer": answer.rawValue,
            "prompt": SessionRules.isFiveMinutePrompt(s) ? "fiveMinutes" : "stillOnThis",
        ])
        if answer == .stop { log(.sessionEnded, task: s.taskID, ["endedBy": SessionEnd.user.rawValue]) }
        now = Date()
        onSessionChange?(openSession, sessionTask)
    }

    func stopSession() {
        guard let s = openSession else { return }
        persist(sessions: [SessionRules.answer(s, .stop, now: Date())])
        log(.sessionEnded, task: s.taskID, ["endedBy": SessionEnd.user.rawValue])
        onSessionChange?(nil, nil)
    }

    func noteCheckInShown() {
        guard let s = openSession else { return }
        log(.checkInShown, task: s.taskID)
    }

    // MARK: Plumbing

    private func persist(tasks changed: [TaskSnapshot] = [], sessions: [SessionSnapshot] = []) {
        guard let repository, !(changed.isEmpty && sessions.isEmpty) else { return }
        do {
            try repository.save(tasks: changed, sessions: sessions)
        } catch {
            problem = String(localized: "That change didn't save. Try again.")
        }
        reload()
    }

    func log(_ kind: ActivityKind, task: UUID?, _ payload: [String: String] = [:]) {
        try? activity?.append(ActivityEvent(at: Date(), kind: kind, taskID: task, payload: payload))
    }

    private func describe(_ day: PlanDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }
}
