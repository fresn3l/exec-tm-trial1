import EFCore
import SwiftUI

struct TodayScreen: View {
    let planner: PlannerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NowCard(planner: planner)
                CarriedRowView(planner: planner)
                mustsSection
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Today")
    }

    private var mustsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.headline)
                Text("Up to \(planner.cap) is plenty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if planner.musts.isEmpty && planner.doneToday.isEmpty {
                Text("Nothing on Today yet. Add something from the Inbox when you're ready.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            List {
                ForEach(planner.musts) { task in
                    TaskRow(planner: planner, task: task, context: .today)
                }
                .onMove { planner.moveMust(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: CGFloat(planner.musts.count) * 44)

            ForEach(planner.doneToday) { task in
                Label(task.title, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .strikethrough()
                    .padding(.leading, 4)
            }
        }
    }
}

/// D-08: one thing, big. Start or start small.
struct NowCard: View {
    let planner: PlannerModel

    var body: some View {
        let result = planner.nowResult
        VStack(alignment: .leading, spacing: 12) {
            if let pick = result.now, let task = planner.task(pick.taskID) {
                HStack(alignment: .firstTextBaseline) {
                    Text(caption(for: pick.source))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    if pick.source == .pinned {
                        Button("Unpin") { planner.unpin() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                Text(task.title)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                FirstStepField(planner: planner, task: task)
                if pick.source == .session {
                    SessionStrip(planner: planner)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            planner.startSession(task.id, mode: .fiveMinutes)
                        } label: {
                            Label("Just 5 minutes", systemImage: "timer")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Start") { planner.startSession(task.id, mode: .standard) }
                            .controlSize(.large)
                        Spacer()
                        Button("Done") { planner.complete(task.id) }
                            .controlSize(.large)
                    }
                }
                if let next = result.next, let nextTask = planner.task(next.taskID) {
                    Divider()
                    HStack {
                        Text("Next").font(.caption).foregroundStyle(.secondary)
                        Text(nextTask.title).lineLimit(1)
                    }
                }
            } else {
                Text("Pick one").font(.title2.weight(.semibold))
                if result.candidates.isEmpty {
                    Text("Nothing waiting. Press ⌃⌥Space anywhere to jot something down.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(result.candidates, id: \.self) { id in
                        if let task = planner.task(id) {
                            HStack {
                                Text(task.title)
                                Spacer()
                                Button("Make this Now") { planner.pin(id) }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func caption(for source: NowRule.Source) -> LocalizedStringKey {
        switch source {
        case .session: "Working on"
        case .pinned: "Now (pinned)"
        case .currentBlock: "Now (scheduled)"
        case .must: "Now"
        case .upcomingBlock: "Coming up"
        }
    }
}

/// "What's the first physical step?" — optional, edited in place.
struct FirstStepField: View {
    let planner: PlannerModel
    let task: TaskSnapshot
    @State private var text = ""

    var body: some View {
        TextField("First step (optional) — e.g. open the file", text: $text)
            .textFieldStyle(.plain)
            .font(.title3)
            .foregroundStyle(.secondary)
            .onAppear { text = task.firstStep ?? "" }
            .onChange(of: task.id) { text = task.firstStep ?? "" }
            .onSubmit { planner.edit(task.id, firstStep: .some(text)) }
            .onDisappear {
                if text != (task.firstStep ?? "") { planner.edit(task.id, firstStep: .some(text)) }
            }
    }
}

/// Shown inside the Now card while a session runs.
struct SessionStrip: View {
    let planner: PlannerModel

    var body: some View {
        if let session = planner.openSession {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    TimelineView(.periodic(from: session.start, by: 1)) { context in
                        Text(timerText(session: session, now: context.date))
                            .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                    }
                    if let estimate = planner.sessionTask?.estimateMinutes {
                        Text("of \(estimate) min").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop") { planner.stopSession() }
                    Button("Done") { planner.complete(session.taskID) }
                        .buttonStyle(.borderedProminent)
                }
                if planner.isCheckInDue {
                    CheckInPrompt(planner: planner)
                }
            }
        }
    }
}

func timerText(session: SessionSnapshot, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(session.start)))
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// D-14 / D-27 prompt. Same three answers everywhere (card, timer, notification).
struct CheckInPrompt: View {
    let planner: PlannerModel

    var body: some View {
        HStack(spacing: 10) {
            Text(planner.isFiveMinutePrompt ? "Five minutes in. Keep going?" : "Still on this?")
                .font(.headline)
            Spacer()
            Button(planner.isFiveMinutePrompt ? "Keep going" : "Yes") { planner.answerCheckIn(.keepGoing) }
                .buttonStyle(.borderedProminent)
            Button("Done") { planner.answerCheckIn(.done) }
            Button(planner.isFiveMinutePrompt ? "Stop here" : "Stop") { planner.answerCheckIn(.stop) }
        }
        .padding(10)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// D-06: non-blocking, at most 3 visible, no red, no badge.
struct CarriedRowView: View {
    let planner: PlannerModel

    var body: some View {
        let row = planner.carriedRow
        if !row.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("From yesterday").font(.headline)
                    Spacer()
                    Button("Keep all as Later") { planner.keepAllAsLater() }
                        .buttonStyle(.link)
                }
                ForEach(row.visible) { task in
                    HStack {
                        Text(task.title).lineLimit(1)
                        Spacer()
                        Button("Today") { planner.triage(task.id, .today) }
                        Button("Later") { planner.triage(task.id, .later) }
                        Button("Drop") { planner.triage(task.id, .drop) }
                    }
                    .controlSize(.small)
                }
                if row.moreCount > 0 {
                    Text("+\(row.moreCount) more").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
