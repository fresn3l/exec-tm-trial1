import EFCore
import SwiftUI

/// D-25 label: minute resolution, never red.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let label = model.planner.statusLabel(nextEventStart: model.nextEventStart)
        if let title = label.taskTitle {
            Text(Self.text(title: title, time: label.time))
        } else {
            Image(systemName: "checklist")
                .accessibilityLabel("ExecFn")
        }
    }

    static func text(title: String, time: StatusLine.Time?) -> String {
        let short = title.count > 22 ? String(title.prefix(21)) + "…" : title
        guard let time else { return short }
        switch time {
        case let .remaining(m): return String(localized: "\(short) · \(m)m left")
        case let .over(m): return String(localized: "\(short) · +\(m)m")
        case let .elapsed(m): return String(localized: "\(short) · \(m)m")
        case let .untilEvent(m): return String(localized: "\(short) · next event in \(m)m")
        }
    }
}

struct MenuBarContent: View {
    let model: AppModel
    let openCapture: () -> Void
    let showTimer: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let planner = model.planner!
        let result = planner.nowResult
        VStack(alignment: .leading, spacing: 10) {
            if let pick = result.now, let task = planner.task(pick.taskID) {
                Text(pick.source == .session ? "Working on" : "Now")
                    .font(.caption).foregroundStyle(.secondary)
                Text(task.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let step = task.firstStep {
                    Text(step).foregroundStyle(.secondary)
                }
                if let session = planner.openSession, session.taskID == task.id {
                    TimelineView(.periodic(from: session.start, by: 1)) { context in
                        Text(timerText(session: session, now: context.date))
                            .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                    }
                    if planner.isCheckInDue {
                        CheckInPrompt(planner: planner).controlSize(.small)
                    } else {
                        HStack {
                            Button("Show timer", action: showTimer)
                            Button("Stop") { planner.stopSession() }
                            Spacer()
                            Button("Done") { planner.complete(task.id) }.buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    HStack {
                        Button("Just 5 minutes") { planner.startSession(task.id, mode: .fiveMinutes) }
                            .buttonStyle(.borderedProminent)
                        Button("Start") { planner.startSession(task.id, mode: .standard) }
                        Spacer()
                        Button("Done") { planner.complete(task.id) }
                    }
                }
                if let next = result.next, let nextTask = planner.task(next.taskID) {
                    Text("Next: \(nextTask.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Pick one").font(.headline)
                ForEach(result.candidates, id: \.self) { id in
                    if let t = planner.task(id) {
                        Button(t.title) { planner.pin(id) }.buttonStyle(.link)
                    }
                }
                if result.candidates.isEmpty {
                    Text("Nothing waiting.").foregroundStyle(.secondary)
                }
            }
            if let next = model.nextEventStart {
                Text("Next event \(next, style: .relative)").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Jot something down", action: openCapture)
                Text("⌃⌥Space").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Open ExecFn") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}
