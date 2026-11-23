import Foundation

/// D-11 / D-13. Proposals only land in free time. A block the user drags may overlap anything.
public enum Scheduling {
    public struct Interval: Hashable, Sendable {
        public var start: Date
        public var end: Date

        public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

        public func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// 5:00–21:00 by default, on the plan day's civil date.
    public static func window(on day: PlanDay, boundary: DayBoundary, settings: PlannerSettings) -> Interval {
        Interval(
            start: boundary.clockTime(on: day, minutesFromMidnight: settings.planningWindowStartMinutes),
            end: boundary.clockTime(on: day, minutesFromMidnight: settings.planningWindowEndMinutes)
        )
    }

    /// Free gaps inside the planning window. Busy calendar time (plus buffer and travel) and
    /// unresolved blocks are removed. Visible events are not. Gaps snap to `proposalSnapMinutes`.
    public static func freeSlots(
        events: [ClassifiedEvent],
        blocks: [BlockSnapshot],
        annotations: [EventAnnotation] = [],
        day: PlanDay,
        boundary: DayBoundary,
        settings: PlannerSettings
    ) -> [Interval] {
        let window = window(on: day, boundary: boundary, settings: settings)
        guard window.end > window.start else { return [] }
        let busy = occupied(events: events, blocks: blocks, annotations: annotations, settings: settings)
        let raw = subtract(window, busy)
        return raw.compactMap { snap($0, minutes: settings.proposalSnapMinutes, calendar: boundary.calendar) }
    }

    public static func slot(containing date: Date, in slots: [Interval]) -> Interval? {
        slots.first { $0.contains(date) }
    }

    /// The earliest snapped gap at or after `after` that can hold `minutes`.
    public static func nextSlot(
        fitting minutes: Int,
        after: Date,
        in slots: [Interval],
        snapMinutes: Int,
        calendar: Calendar
    ) -> Interval? {
        let need = max(snapMinutes, (minutes / snapMinutes) * snapMinutes)
        for slot in slots {
            let start = ceil(max(slot.start, after), minutes: snapMinutes, calendar: calendar)
            guard slot.end.timeIntervalSince(start) >= TimeInterval(need * 60) else { continue }
            return Interval(start: start, end: slot.end)
        }
        return nil
    }

    /// A ghost block. Nil when the gap cannot hold one snap. Length is the estimate, or
    /// `defaultBlockMinutes`, rounded to the nearest snap and clipped to the gap.
    public static func propose(
        task: TaskSnapshot,
        in gap: Interval,
        settings: PlannerSettings,
        id: UUID = UUID()
    ) -> BlockSnapshot? {
        let snap = max(1, settings.proposalSnapMinutes)
        let desired = (task.estimateMinutes ?? 0) > 0 ? task.estimateMinutes! : settings.defaultBlockMinutes
        let rounded = max(snap, Int((Double(desired) / Double(snap)).rounded()) * snap)
        let fit = (gap.minutes / snap) * snap
        guard fit >= snap else { return nil }
        let length = min(rounded, fit)
        return BlockSnapshot(
            id: id,
            taskID: task.id,
            start: gap.start,
            end: gap.start.addingTimeInterval(TimeInterval(length * 60))
        )
    }

    /// Drag. Duration stays put. The new start snaps to the nearest grid line and may leave the window.
    public static func moved(
        _ block: BlockSnapshot,
        toStart raw: Date,
        settings: PlannerSettings,
        calendar: Calendar
    ) -> BlockSnapshot {
        let duration = max(block.end.timeIntervalSince(block.start), TimeInterval(settings.proposalSnapMinutes * 60))
        var copy = block
        copy.start = nearest(raw, minutes: settings.proposalSnapMinutes, calendar: calendar)
        copy.end = copy.start.addingTimeInterval(duration)
        copy.resolution = nil
        return copy
    }

    /// Resize from the bottom. The end snaps to the grid. The block stays at least one snap long.
    public static func resized(
        _ block: BlockSnapshot,
        toEnd raw: Date,
        settings: PlannerSettings,
        calendar: Calendar
    ) -> BlockSnapshot {
        let minimum = TimeInterval(max(1, settings.proposalSnapMinutes) * 60)
        var copy = block
        let snapped = nearest(raw, minutes: settings.proposalSnapMinutes, calendar: calendar)
        copy.end = max(snapped, block.start.addingTimeInterval(minimum))
        copy.resolution = nil
        return copy
    }

    // MARK: Internals

    private static func occupied(
        events: [ClassifiedEvent],
        blocks: [BlockSnapshot],
        annotations: [EventAnnotation],
        settings: PlannerSettings
    ) -> [Interval] {
        let buffer = TimeInterval(settings.defaultBufferMinutes * 60)
        let travelByRef = Dictionary(uniqueKeysWithValues: annotations.map { ($0.ref, $0.travelMinutes ?? 0) })
        var busy: [Interval] = []
        for item in events where item.blocksTime {
            if item.event.isAllDay { continue }
            let travel = TimeInterval((travelByRef[item.event.ref] ?? 0) * 60)
            busy.append(Interval(
                start: item.event.start.addingTimeInterval(-(buffer + travel)),
                end: item.event.end.addingTimeInterval(buffer)
            ))
        }
        if events.contains(where: { $0.blocksTime && $0.event.isAllDay }) {
            busy.append(Interval(start: .distantPast, end: .distantFuture))
        }
        for block in blocks where block.resolution == nil && block.end > block.start {
            busy.append(Interval(start: block.start, end: block.end))
        }
        return busy
    }

    private static func subtract(_ window: Interval, _ busy: [Interval]) -> [Interval] {
        var free = [window]
        for item in busy {
            free = free.flatMap { gap -> [Interval] in
                if item.end <= gap.start || item.start >= gap.end { return [gap] }
                var parts: [Interval] = []
                if item.start > gap.start { parts.append(Interval(start: gap.start, end: item.start)) }
                if item.end < gap.end { parts.append(Interval(start: item.end, end: gap.end)) }
                return parts
            }
        }
        return free.filter { $0.end > $0.start }
    }

    private static func snap(_ gap: Interval, minutes: Int, calendar: Calendar) -> Interval? {
        let start = ceil(gap.start, minutes: minutes, calendar: calendar)
        let end = floor(gap.end, minutes: minutes, calendar: calendar)
        guard end.timeIntervalSince(start) >= TimeInterval(minutes * 60) else { return nil }
        return Interval(start: start, end: end)
    }

    static func ceil(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        let snapped = aligned(date, minutes: minutes, calendar: calendar)
        return snapped < date ? snapped.addingTimeInterval(TimeInterval(minutes * 60)) : snapped
    }

    static func floor(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        let snapped = aligned(date, minutes: minutes, calendar: calendar)
        return snapped > date ? snapped.addingTimeInterval(TimeInterval(-minutes * 60)) : snapped
    }

    static func nearest(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        let down = floor(date, minutes: minutes, calendar: calendar)
        let up = ceil(date, minutes: minutes, calendar: calendar)
        return date.timeIntervalSince(down) <= up.timeIntervalSince(date) ? down : up
    }

    /// The grid line at or before `date`, ignoring seconds by flooring the minute first.
    private static func aligned(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        let step = max(1, minutes)
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = parts.minute ?? 0
        parts.minute = minute - (minute % step)
        parts.second = 0
        return calendar.date(from: parts) ?? date
    }
}
