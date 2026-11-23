import AppKit
import EFCore
import EFPersistence
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    let settingsStore: SettingsStore
    var settings: PlannerSettings
    var selectedDay: PlanDay
    let calendar = CalendarService()
    private var activityLog: ActivityLog?
    private var recordedAccess: CalendarService.Access?
    var storeProblem: String?
    var exportMessage: String?
    /// Tasks, sessions, pin, rollover. Shares the main store's one context (D-01).
    private(set) var planner: PlannerModel!
    private var started = false

    init() {
        let store = SettingsStore.appGroup()
        settingsStore = store
        let loaded = store.load()
        settings = loaded
        let opening = DayBoundary(hour: loaded.dayBoundaryHour, timeZone: .current)
        selectedDay = opening.planDay(containing: Date())
        var repository: TaskRepository?
        do {
            let opened = try ExecFnStoreFactory.make()
            activityLog = ActivityLog(container: opened.activity)
            repository = TaskRepository(container: opened.main)
        } catch {
            storeProblem = String(localized: "The local store didn't open.")
        }
        planner = PlannerModel(
            repository: repository,
            activity: activityLog,
            pins: .appGroup(),
            settings: { [unowned self] in self.settings }
        )
    }

    /// Start of the next timed, non-hidden event today, for the menu bar (D-25).
    var nextEventStart: Date? {
        guard selectedDay == today else { return nil }
        return StatusLine.nextEventStart(
            events: dayContent.timed.map(\.event),
            now: planner.now,
            dayEnd: boundary.end(of: today)
        )
    }

    var boundary: DayBoundary {
        DayBoundary(hour: settings.dayBoundaryHour, timeZone: .current)
    }

    var today: PlanDay {
        boundary.planDay(containing: Date())
    }

    var dayContent: DayCalendar {
        CalendarRules.assemble(
            events: calendar.events,
            calendars: calendar.calendars,
            settings: settings,
            day: selectedDay,
            boundary: boundary
        )
    }

    var dayTitle: String {
        boundary.start(of: selectedDay).formatted(
            .dateTime.weekday(.wide).month(.wide).day().year()
        )
    }

    func start() async {
        guard !started else { return }
        started = true
        planner.start()
        await calendar.prepare(requestingIfNeeded: true)
        recordAccessIfNeeded()
        show(selectedDay)
    }

    func show(_ day: PlanDay) {
        selectedDay = day
        calendar.setRange(start: boundary.start(of: day), end: boundary.end(of: day))
    }

    func shift(by days: Int) {
        show(selectedDay.advanced(by: days))
    }

    func mode(for descriptor: CalendarDescriptor) -> CalendarMode {
        CalendarRules.mode(for: descriptor, among: calendar.calendars, settings: settings)
    }

    func setMode(_ mode: CalendarMode, for descriptor: CalendarDescriptor) {
        settings.calendarModes[descriptor.id] = CalendarModeOverride(mode: mode, title: descriptor.title)
        settingsStore.save(settings)
    }

    func clearMode(for descriptor: CalendarDescriptor) {
        settings.calendarModes.removeValue(forKey: descriptor.id)
        settingsStore.save(settings)
    }

    func hasOverride(for descriptor: CalendarDescriptor) -> Bool {
        settings.calendarModes[descriptor.id] != nil
    }

    func requestAccess() async {
        await calendar.requestAccess()
        recordAccessIfNeeded()
        show(selectedDay)
    }

    func openCalendarSettings() {
        SystemSettingsOpener.openCalendars()
    }

    func exportActivityLog() {
        guard let activityLog else {
            exportMessage = String(localized: "The local store didn't open.")
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ExecFn-activity.jsonl"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try activityLog.exportJSONL().write(to: url, atomically: true, encoding: .utf8)
            exportMessage = String(localized: "Saved the activity log.")
        } catch {
            exportMessage = String(localized: "The activity log didn't save.")
        }
    }

    private func recordAccessIfNeeded() {
        guard recordedAccess != calendar.access, calendar.access != .unknown else { return }
        recordedAccess = calendar.access
        try? activityLog?.append(
            ActivityEvent(
                at: Date(),
                kind: .calendarAccessChanged,
                payload: ["state": calendar.access.rawValue]
            )
        )
    }
}
