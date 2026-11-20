import Foundation

public struct CalendarDescriptor: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isBirthday: Bool
    public var isSubscribed: Bool

    public init(id: String, title: String, isBirthday: Bool = false, isSubscribed: Bool = false) {
        self.id = id
        self.title = title
        self.isBirthday = isBirthday
        self.isSubscribed = isSubscribed
    }
}

public struct ClassifiedEvent: Identifiable, Hashable, Sendable {
    public var event: EventSnapshot
    public var mode: CalendarMode
    public var blocksTime: Bool

    public var id: EventRef { event.ref }

    public init(event: EventSnapshot, mode: CalendarMode, blocksTime: Bool) {
        self.event = event
        self.mode = mode
        self.blocksTime = blocksTime
    }
}

public struct DayCalendar: Hashable, Sendable {
    public var allDay: [ClassifiedEvent]
    public var timed: [ClassifiedEvent]

    public init(allDay: [ClassifiedEvent] = [], timed: [ClassifiedEvent] = []) {
        self.allDay = allDay
        self.timed = timed
    }
}

/// Where a timed event sits inside a plan day, as fractions of that day's real duration.
/// A fall-back day is 25 hours and a spring-forward day that contains 2 AM is 23.
public struct DayFraction: Hashable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public enum CalendarRules {
    public static func defaultMode(for calendar: CalendarDescriptor) -> CalendarMode {
        if calendar.isBirthday || calendar.isSubscribed || isHolidayTitle(calendar.title) {
            return .visible
        }
        return .busy
    }

    /// Identifier match wins. A stored override whose identifier is no longer
    /// in `calendars` can match by title, and only when that title is unique
    /// among those stale overrides.
    public static func mode(
        for calendar: CalendarDescriptor,
        among calendars: [CalendarDescriptor],
        settings: PlannerSettings
    ) -> CalendarMode {
        if let override = settings.calendarModes[calendar.id] {
            return override.mode
        }
        let liveIDs = Set(calendars.map(\.id))
        let staleMatches = settings.calendarModes.filter { entry in
            !liveIDs.contains(entry.key)
                && entry.value.title.compare(calendar.title, options: .caseInsensitive) == .orderedSame
        }
        if staleMatches.count == 1, let match = staleMatches.first {
            return match.value.mode
        }
        return defaultMode(for: calendar)
    }

    /// Hidden and Visible never reserve time.
    /// Not-supported availability is treated as free.
    /// All-day events reserve time only when they are busy or unavailable.
    /// Timed events on a Busy calendar reserve time for busy, tentative, and unavailable.
    public static func blocksTime(event: EventSnapshot, mode: CalendarMode) -> Bool {
        guard mode == .busy else { return false }
        switch event.availability {
        case .free, .notSupported:
            return false
        case .busy, .unavailable:
            return true
        case .tentative:
            return !event.isAllDay
        }
    }

    /// All-day events belong to the civil dates they cover, not to whichever
    /// plan day happens to overlap midnight. Timed events use plan-day overlap.
    public static func contains(
        _ event: EventSnapshot,
        on day: PlanDay,
        boundary: DayBoundary
    ) -> Bool {
        if event.isAllDay {
            return allDayPlanDays(for: event, calendar: boundary.calendar).contains(day)
        }
        let start = boundary.start(of: day)
        let end = boundary.end(of: day)
        return event.start < end && event.end > start
    }

    public static func fraction(
        of event: EventSnapshot,
        on day: PlanDay,
        boundary: DayBoundary
    ) -> DayFraction? {
        guard !event.isAllDay, contains(event, on: day, boundary: boundary) else { return nil }
        let dayStart = boundary.start(of: day)
        let dayEnd = boundary.end(of: day)
        let duration = dayEnd.timeIntervalSince(dayStart)
        guard duration > 0 else { return nil }
        let start = max(event.start, dayStart)
        let end = min(event.end, dayEnd)
        guard end > start else { return nil }
        return DayFraction(
            start: start.timeIntervalSince(dayStart) / duration,
            end: end.timeIntervalSince(dayStart) / duration
        )
    }

    public static func assemble(
        events: [EventSnapshot],
        calendars: [CalendarDescriptor],
        settings: PlannerSettings,
        day: PlanDay,
        boundary: DayBoundary
    ) -> DayCalendar {
        let known = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0) })
        var allDay: [ClassifiedEvent] = []
        var timed: [ClassifiedEvent] = []

        for event in events {
            let descriptor = known[event.calendarID]
                ?? CalendarDescriptor(id: event.calendarID, title: "")
            let resolved = mode(for: descriptor, among: calendars, settings: settings)
            guard resolved != .hidden else { continue }
            guard contains(event, on: day, boundary: boundary) else { continue }
            let classified = ClassifiedEvent(
                event: event,
                mode: resolved,
                blocksTime: blocksTime(event: event, mode: resolved)
            )
            if event.isAllDay {
                allDay.append(classified)
            } else {
                timed.append(classified)
            }
        }

        allDay.sort { $0.event.title.localizedCaseInsensitiveCompare($1.event.title) == .orderedAscending }
        timed.sort {
            if $0.event.start != $1.event.start { return $0.event.start < $1.event.start }
            return $0.event.title.localizedCaseInsensitiveCompare($1.event.title) == .orderedAscending
        }
        return DayCalendar(allDay: allDay, timed: timed)
    }

    static func allDayPlanDays(for event: EventSnapshot, calendar: Calendar) -> [PlanDay] {
        let startParts = calendar.dateComponents([.year, .month, .day], from: event.start)
        let endParts = calendar.dateComponents([.year, .month, .day], from: event.end)
        guard
            let startYear = startParts.year, let startMonth = startParts.month, let startDay = startParts.day,
            let endYear = endParts.year, let endMonth = endParts.month, let endDay = endParts.day
        else {
            return []
        }
        let start = PlanDay(year: startYear, month: startMonth, day: startDay)
        let end = PlanDay(year: endYear, month: endMonth, day: endDay)
        if end < start { return [] }
        if end == start { return [start] }
        var days: [PlanDay] = []
        var cursor = start
        var steps = 0
        while cursor < end && steps < 400 {
            days.append(cursor)
            cursor = cursor.advanced(by: 1)
            steps += 1
        }
        return days.isEmpty ? [start] : days
    }

    private static func isHolidayTitle(_ title: String) -> Bool {
        title.range(of: "holiday", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
