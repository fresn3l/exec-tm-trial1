import EFCore
import SwiftUI

struct DayScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if let storeProblem = model.storeProblem {
                notice(storeProblem)
            }
            if let noticeText = accessNotice {
                notice(noticeText, actions: accessActions)
            }
            allDayStrip
            timeline
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { await model.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous day")
            .accessibilityLabel("Previous day")

            Text(model.dayTitle)
                .font(.title2.weight(.semibold))

            Button {
                model.shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next day")
            .accessibilityLabel("Next day")

            if model.selectedDay != model.today {
                Button("Today") { model.show(model.today) }
            }

            Spacer()

            Text("Solid reserves time. Dashed stays visible and leaves the time open.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 240)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var allDayStrip: some View {
        if !model.dayContent.allDay.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("All day")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ForEach(model.dayContent.allDay) { item in
                        allDayChip(item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    private var timeline: some View {
        let boundary = model.boundary
        let day = model.selectedDay
        let start = boundary.start(of: day)
        let end = boundary.end(of: day)
        let seconds = max(end.timeIntervalSince(start), 1)
        let height = hourHeight * seconds / 3600
        let placed = columns(for: model.dayContent.timed, day: day, boundary: boundary)

        return ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid(start: start, end: end, height: height, boundary: boundary)
                    ForEach(model.dayContent.timed) { item in
                        if let fraction = CalendarRules.fraction(of: item.event, on: day, boundary: boundary) {
                            timedBlock(item, fraction: fraction, height: height, placement: placed[item.id])
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if context.date >= start, context.date < end {
                            let fraction = context.date.timeIntervalSince(start) / seconds
                            nowLine
                                .offset(y: height * fraction)
                                .id("now-line")
                        }
                    }
                }
                .frame(height: height, alignment: .top)
                .padding(.trailing, 16)
            }
            .onAppear { scroll(proxy, start: start, end: end, boundary: boundary) }
            .onChange(of: model.selectedDay) { _, _ in
                scroll(proxy, start: start, end: end, boundary: boundary)
            }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.leading, 48)
        .accessibilityLabel("Now")
    }

    private func hourGrid(start: Date, end: Date, height: CGFloat, boundary: DayBoundary) -> some View {
        let marks = hourMarks(start: start, end: end, calendar: boundary.calendar)
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.id) { mark in
                HStack(alignment: .top, spacing: 8) {
                    Text(mark.label)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 52, alignment: .trailing)
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
                .offset(y: height * mark.fraction)
                .id(mark.id)
            }
        }
    }

    private func timedBlock(
        _ item: ClassifiedEvent,
        fraction: DayFraction,
        height: CGFloat,
        placement: ColumnPlacement?
    ) -> some View {
        let column = placement?.column ?? 0
        let count = max(placement?.count ?? 1, 1)
        let top = height * fraction.start
        let blockHeight = max(height * (fraction.end - fraction.start), 28)
        return GeometryReader { geometry in
            let lane = max(geometry.size.width - 76, 40) / CGFloat(count)
            eventCard(item)
                .frame(width: lane - 6, height: blockHeight, alignment: .topLeading)
                .offset(x: 68 + lane * CGFloat(column), y: top)
        }
    }

    private func eventCard(_ item: ClassifiedEvent) -> some View {
        let reserves = item.blocksTime
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.event.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Text(timeRange(item.event))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !reserves {
                Text("Doesn't reserve time")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(reserves ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    reserves ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.7),
                    style: StrokeStyle(lineWidth: reserves ? 2 : 1, dash: reserves ? [] : [3, 3])
                )
        )
    }

    private func allDayChip(_ item: ClassifiedEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.event.title)
                .font(.callout)
            if item.blocksTime {
                Text("Blocks time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.blocksTime ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    item.blocksTime ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1, dash: item.blocksTime ? [] : [3, 3])
                )
        )
    }

    @ViewBuilder
    private func notice(_ text: String, actions: AnyView? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            if let actions {
                actions
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }

    private var accessNotice: String? {
        switch model.calendar.access {
        case .unknown, .notDetermined:
            return String(localized: "Checking calendar access")
        case .denied:
            return String(localized: "Calendar access is off. The day still works without events.")
        case .restricted:
            return String(localized: "Calendar access is restricted on this Mac.")
        case .writeOnly:
            return String(localized: "Calendar access is write-only. Full access is what shows events.")
        case .full:
            return model.dayContent.allDay.isEmpty && model.dayContent.timed.isEmpty
                ? String(localized: "Nothing on this day from the calendars you're showing.")
                : nil
        }
    }

    private var accessActions: AnyView? {
        switch model.calendar.access {
        case .notDetermined:
            return AnyView(Button("Allow Calendar Access") { Task { await model.requestAccess() } })
        case .denied, .restricted, .writeOnly:
            return AnyView(Button("Open System Settings") { model.openCalendarSettings() })
        case .unknown, .full:
            return nil
        }
    }

    private func timeRange(_ event: EventSnapshot) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
    }

    private func scroll(_ proxy: ScrollViewProxy, start: Date, end: Date, boundary: DayBoundary) {
        let now = Date()
        if now >= start, now < end {
            proxy.scrollTo("now-line", anchor: .center)
            return
        }
        let marks = hourMarks(start: start, end: end, calendar: boundary.calendar)
        let morning = marks.first { boundary.calendar.component(.hour, from: Date(timeIntervalSince1970: $0.instant)) == 8 }
        proxy.scrollTo(morning?.id ?? marks.first?.id ?? "now-line", anchor: .top)
    }

    private func hourMarks(start: Date, end: Date, calendar: Calendar) -> [HourMark] {
        var marks: [HourMark] = []
        var cursor = start
        let duration = end.timeIntervalSince(start)
        while cursor < end {
            let fraction = cursor.timeIntervalSince(start) / duration
            marks.append(
                HourMark(
                    id: "hour-\(cursor.timeIntervalSince1970)",
                    instant: cursor.timeIntervalSince1970,
                    fraction: fraction,
                    label: cursor.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                )
            )
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return marks
    }

    private func columns(
        for events: [ClassifiedEvent],
        day: PlanDay,
        boundary: DayBoundary
    ) -> [EventRef: ColumnPlacement] {
        let items: [(EventRef, Double, Double)] = events.compactMap { item in
            guard let fraction = CalendarRules.fraction(of: item.event, on: day, boundary: boundary) else { return nil }
            return (item.id, fraction.start, fraction.end)
        }
        let sorted = items.sorted { $0.1 < $1.1 }
        var columnOf: [EventRef: Int] = [:]
        var active: [(EventRef, Double, Int)] = []
        var cluster: [EventRef] = []
        var clusters: [[EventRef]] = []
        for item in sorted {
            active.removeAll { $0.1 <= item.1 }
            if active.isEmpty, !cluster.isEmpty {
                clusters.append(cluster)
                cluster = []
            }
            let used = Set(active.map(\.2))
            var column = 0
            while used.contains(column) { column += 1 }
            columnOf[item.0] = column
            active.append((item.0, item.2, column))
            cluster.append(item.0)
        }
        if !cluster.isEmpty { clusters.append(cluster) }
        var placed: [EventRef: ColumnPlacement] = [:]
        for group in clusters {
            let count = (group.compactMap { columnOf[$0] }.max() ?? 0) + 1
            for id in group {
                placed[id] = ColumnPlacement(column: columnOf[id] ?? 0, count: count)
            }
        }
        return placed
    }
}

private struct HourMark {
    var id: String
    var instant: TimeInterval
    var fraction: Double
    var label: String
}

private struct ColumnPlacement {
    var column: Int
    var count: Int
}

private let hourHeight: CGFloat = 52
