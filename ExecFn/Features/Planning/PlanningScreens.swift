import EFCore
import SwiftUI

struct PassedTimePrompt: View {
    let planner: PlannerModel
    let block: BlockSnapshot
    let task: TaskSnapshot
    @State private var dayIsFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This time has passed.")
                .font(.headline)
            Text(task.title)
            Text(range)
                .font(.caption)
                .foregroundStyle(.secondary)
            if dayIsFull {
                Text("The day is full.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Reschedule") {
                    dayIsFull = !planner.reschedulePassed()
                }
                Button("Leave it") { planner.leavePassed() }
                Button("I did it") { planner.markPassedDone() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.08))
        .onChange(of: block.id) { _, _ in dayIsFull = false }
    }

    private var range: String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(block.start.formatted(style)) – \(block.end.formatted(style))"
    }
}

struct RoutineRowView: View {
    let planner: PlannerModel

    var body: some View {
        let row = planner.routinesToday
        if !row.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Routines").font(.headline)
                ForEach(row) { task in
                    HStack {
                        Button {
                            planner.complete(task.id)
                        } label: {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Done")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                            checklist(task)
                        }
                        Spacer()
                        Button("Start") { planner.startSession(task.id, mode: .standard) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checklist(_ task: TaskSnapshot) -> some View {
        let items = planner.subtasks(for: task.id)
        if !items.isEmpty {
            ForEach(items) { item in
                Button {
                    planner.toggleSubtask(item.id)
                } label: {
                    Label(item.title, systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct FreshStartButton: View {
    let planner: PlannerModel
    @State private var showing = false
    @State private var moveUntouched = false

    var body: some View {
        Button("Fresh start") { showing = true }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .sheet(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Fresh start").font(.title3.weight(.semibold))
                    Text("Clears Today and anything carried from yesterday. Blocks and finished tasks stay.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Also move anything untouched for \(planner.settings.somedayAfterDays) days to Someday", isOn: $moveUntouched)
                    HStack {
                        Button("Cancel", role: .cancel) { showing = false }
                        Spacer()
                        Button("Start fresh") {
                            planner.freshStart(moveUntouchedToSomeday: moveUntouched)
                            showing = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .frame(width: 440)
            }
    }
}

struct SomedayScreen: View {
    let planner: PlannerModel

    var body: some View {
        Group {
            if planner.somedayTasks.isEmpty {
                ContentUnavailableView(
                    "Someday is empty",
                    systemImage: "archivebox",
                    description: Text("Tasks you move here stay out of the Inbox until you bring them back.")
                )
            } else {
                List(planner.somedayTasks) { task in
                    HStack {
                        Text(task.title)
                        Spacer()
                        Button("Bring back") { planner.moveOutOfSomeday(task.id) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("Someday")
    }
}

struct RoutinesScreen: View {
    let planner: PlannerModel
    @State private var title = ""
    @State private var schedule: ScheduleChoice = .daily
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var everyN = 2
    @State private var checklist = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("Title", text: $title)
                Picker("Schedule", selection: $schedule) {
                    Text("Every day").tag(ScheduleChoice.daily)
                    Text("Weekdays").tag(ScheduleChoice.weekdays)
                    Text("Chosen days").tag(ScheduleChoice.weekly)
                    Text("Every few days").tag(ScheduleChoice.everyN)
                }
                if schedule == .weekly {
                    weekdayPicker
                }
                if schedule == .everyN {
                    Stepper("Every \(everyN) days", value: $everyN, in: 1...30)
                }
                TextField("Checklist, one step per line", text: $checklist, axis: .vertical)
                    .lineLimit(3...6)
                Button("Add routine") { add() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .formStyle(.grouped)
            List(planner.routines) { routine in
                HStack {
                    VStack(alignment: .leading) {
                        Text(routine.title)
                        Text(routine.isActive ? scheduleLabel(routine) : "Off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(routine.isActive ? "Turn off" : "Turn on") {
                        var copy = routine
                        copy.isActive.toggle()
                        planner.saveRoutine(copy)
                    }
                    .controlSize(.small)
                }
            }
        }
        .navigationTitle("Routines")
    }

    private var weekdayPicker: some View {
        let names = Calendar.current.shortWeekdaySymbols
        return HStack {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.contains(day)
                Button(names[day - 1]) {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                }
                .buttonStyle(.bordered)
                .tint(on ? Color.accentColor : Color.secondary)
            }
        }
    }

    private func add() {
        let lines = checklist.components(separatedBy: .newlines)
        let template = RoutineTemplate(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: chosenSchedule,
            checklist: lines
        )
        planner.saveRoutine(template)
        title = ""
        checklist = ""
    }

    private var chosenSchedule: RoutineSchedule {
        switch schedule {
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly: .weekly(weekdays)
        case .everyN: .everyNDays(everyN, anchor: planner.today)
        }
    }

    private func scheduleLabel(_ routine: RoutineTemplate) -> String {
        switch routine.schedule {
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Chosen days"
        case .everyNDays(let n, _): "Every \(n) days"
        }
    }

    enum ScheduleChoice: Hashable { case daily, weekdays, weekly, everyN }
}
