import Foundation
import Testing
@testable import EFCore

struct CalendarRulesTests {
    private let zone = TimeZone(identifier: "America/Chicago")!
    private var boundary: DayBoundary { DayBoundary(hour: 4, timeZone: zone) }

    private func utc(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    private func event(
        id: String = "event",
        calendarID: String = "work",
        title: String = "Event",
        start: Date,
        end: Date,
        allDay: Bool = false,
        availability: EventAvailability = .busy
    ) -> EventSnapshot {
        EventSnapshot(
            ref: EventRef(externalID: id, occurrenceStart: start),
            calendarID: calendarID,
            title: title,
            start: start,
            end: end,
            isAllDay: allDay,
            availability: availability,
            hasLocation: false
        )
    }

    @Test func defaultsKeepBirthdaysHolidaysAndSubscriptionsFromReservingTime() {
        #expect(CalendarRules.defaultMode(for: CalendarDescriptor(id: "b", title: "Birthdays", isBirthday: true)) == .visible)
        #expect(CalendarRules.defaultMode(for: CalendarDescriptor(id: "s", title: "Weather", isSubscribed: true)) == .visible)
        #expect(CalendarRules.defaultMode(for: CalendarDescriptor(id: "h", title: "US Holidays")) == .visible)
        #expect(CalendarRules.defaultMode(for: CalendarDescriptor(id: "w", title: "Work")) == .busy)
    }

    @Test func identifierOverrideBeatsTheDefault() {
        let birthday = CalendarDescriptor(id: "b", title: "Birthdays", isBirthday: true)
        var settings = PlannerSettings()
        settings.calendarModes = ["b": CalendarModeOverride(mode: .hidden, title: "Birthdays")]
        #expect(CalendarRules.mode(for: birthday, among: [birthday], settings: settings) == .hidden)
    }

    @Test func staleIdentifierFallsBackToAUniqueTitle() {
        let work = CalendarDescriptor(id: "new-work", title: "Work")
        var settings = PlannerSettings()
        settings.calendarModes = ["old-work": CalendarModeOverride(mode: .hidden, title: "Work")]
        #expect(CalendarRules.mode(for: work, among: [work], settings: settings) == .hidden)
    }

    @Test func ambiguousStaleTitlesDoNotGuess() {
        let work = CalendarDescriptor(id: "new-work", title: "Work")
        var settings = PlannerSettings()
        settings.calendarModes = [
            "old-a": CalendarModeOverride(mode: .hidden, title: "Work"),
            "old-b": CalendarModeOverride(mode: .visible, title: "Work"),
        ]
        #expect(CalendarRules.mode(for: work, among: [work], settings: settings) == .busy)
    }

    @Test func availabilityMatrix() {
        let cases: [(CalendarMode, Bool, EventAvailability, Bool)] = [
            (.hidden, false, .busy, false),
            (.visible, false, .busy, false),
            (.visible, true, .unavailable, false),
            (.busy, false, .busy, true),
            (.busy, false, .tentative, true),
            (.busy, false, .unavailable, true),
            (.busy, false, .free, false),
            (.busy, false, .notSupported, false),
            (.busy, true, .busy, true),
            (.busy, true, .unavailable, true),
            (.busy, true, .tentative, false),
            (.busy, true, .free, false),
            (.busy, true, .notSupported, false),
        ]
        for (mode, allDay, availability, blocks) in cases {
            let sample = event(
                start: utc("2026-11-20T15:00:00Z"),
                end: utc("2026-11-20T16:00:00Z"),
                allDay: allDay,
                availability: availability
            )
            #expect(CalendarRules.blocksTime(event: sample, mode: mode) == blocks)
        }
    }

    @Test func hiddenCalendarsStayOffTheDay() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let calendars = [
            CalendarDescriptor(id: "work", title: "Work"),
            CalendarDescriptor(id: "home", title: "Home"),
        ]
        var settings = PlannerSettings()
        settings.calendarModes = ["home": CalendarModeOverride(mode: .hidden, title: "Home")]
        let events = [
            event(id: "a", calendarID: "work", title: "Standup", start: utc("2026-11-20T15:00:00Z"), end: utc("2026-11-20T15:30:00Z")),
            event(id: "b", calendarID: "home", title: "Dentist", start: utc("2026-11-20T18:00:00Z"), end: utc("2026-11-20T19:00:00Z")),
        ]
        let assembled = CalendarRules.assemble(
            events: events,
            calendars: calendars,
            settings: settings,
            day: day,
            boundary: boundary
        )
        #expect(assembled.timed.map(\.event.title) == ["Standup"])
        #expect(assembled.timed.first?.blocksTime == true)
    }

    @Test func visibleTimedEventRendersWithoutReservingTime() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let calendars = [CalendarDescriptor(id: "hol", title: "US Holidays")]
        let events = [
            event(calendarID: "hol", title: "Talk", start: utc("2026-11-20T16:00:00Z"), end: utc("2026-11-20T17:00:00Z")),
        ]
        let assembled = CalendarRules.assemble(
            events: events,
            calendars: calendars,
            settings: .standard,
            day: day,
            boundary: boundary
        )
        #expect(assembled.timed.count == 1)
        #expect(assembled.timed.first?.mode == .visible)
        #expect(assembled.timed.first?.blocksTime == false)
    }

    @Test func allDayEventUsesCivilDatesNotTheFourAMOverlap() {
        let friday = event(
            title: "Conference",
            start: utc("2026-11-20T06:00:00Z"),
            end: utc("2026-11-21T06:00:00Z"),
            allDay: true,
            availability: .notSupported
        )
        #expect(CalendarRules.contains(friday, on: PlanDay(year: 2026, month: 11, day: 19), boundary: boundary) == false)
        #expect(CalendarRules.contains(friday, on: PlanDay(year: 2026, month: 11, day: 20), boundary: boundary))
        #expect(CalendarRules.contains(friday, on: PlanDay(year: 2026, month: 11, day: 21), boundary: boundary) == false)
    }

    @Test func multiDayAllDayCoversEachCivilDateExceptTheExclusiveEnd() {
        let span = event(
            title: "Trip",
            start: utc("2026-11-20T06:00:00Z"),
            end: utc("2026-11-22T06:00:00Z"),
            allDay: true,
            availability: .busy
        )
        #expect(CalendarRules.contains(span, on: PlanDay(year: 2026, month: 11, day: 20), boundary: boundary))
        #expect(CalendarRules.contains(span, on: PlanDay(year: 2026, month: 11, day: 21), boundary: boundary))
        #expect(CalendarRules.contains(span, on: PlanDay(year: 2026, month: 11, day: 22), boundary: boundary) == false)
    }

    @Test func blockingAllDayStaysInTheStrip() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let calendars = [CalendarDescriptor(id: "work", title: "Work")]
        let events = [
            event(
                calendarID: "work",
                title: "Out of office",
                start: utc("2026-11-20T06:00:00Z"),
                end: utc("2026-11-21T06:00:00Z"),
                allDay: true,
                availability: .unavailable
            ),
        ]
        let assembled = CalendarRules.assemble(
            events: events,
            calendars: calendars,
            settings: .standard,
            day: day,
            boundary: boundary
        )
        #expect(assembled.timed.isEmpty)
        #expect(assembled.allDay.first?.blocksTime == true)
    }

    @Test func timedEventThatEndsBeforeFourDoesNotSpillIntoTheNextPlanDay() {
        let late = event(
            title: "Late",
            start: utc("2026-11-20T05:00:00Z"),
            end: utc("2026-11-20T08:00:00Z")
        )
        // 11 PM Thursday through 2 AM Friday, Chicago. The Friday plan day opens at 4 AM.
        #expect(CalendarRules.contains(late, on: PlanDay(year: 2026, month: 11, day: 19), boundary: boundary))
        #expect(CalendarRules.contains(late, on: PlanDay(year: 2026, month: 11, day: 20), boundary: boundary) == false)
    }

    @Test func fractionClipsToThePlanDay() {
        let day = PlanDay(year: 2026, month: 11, day: 20)
        let spanning = event(
            title: "Overnight",
            start: utc("2026-11-21T09:00:00Z"),
            end: utc("2026-11-21T12:00:00Z")
        )
        let fraction = CalendarRules.fraction(of: spanning, on: day, boundary: boundary)
        // 3 AM–6 AM Chicago. The plan day ends at 4 AM, so only the first hour remains: 23/24 ..< 1.
        #expect(fraction != nil)
        if let fraction {
            #expect(abs(fraction.start - (23.0 / 24.0)) < 0.0001)
            #expect(abs(fraction.end - 1) < 0.0001)
        }
    }
}
