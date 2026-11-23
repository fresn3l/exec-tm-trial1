import EFCore
import SwiftUI

struct InboxScreen: View {
    let planner: PlannerModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Add a task — just a title is enough", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit {
                        if planner.capture(draft, source: .app) { draft = "" }
                        focused = true
                    }
            }
            .padding(16)
            if planner.inbox.isEmpty {
                ContentUnavailableView(
                    "Inbox is clear",
                    systemImage: "tray",
                    description: Text("Anything you jot down with ⌃⌥Space lands here.")
                )
            } else {
                List(planner.inbox) { task in
                    TaskRow(planner: planner, task: task, context: .inbox)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Inbox")
    }
}

struct TaskRow: View {
    enum Context { case inbox, today }
    let planner: PlannerModel
    let task: TaskSnapshot
    let context: Context
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                planner.complete(task.id)
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.borderless)
            .help("Done")
            .accessibilityLabel("Done")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                if let step = task.firstStep {
                    Text(step).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let estimate = task.estimateMinutes {
                Text("\(estimate) min").font(.caption).foregroundStyle(.secondary)
            }
            if planner.pinnedTaskID == task.id {
                Image(systemName: "pin.fill").foregroundStyle(.secondary).accessibilityLabel("Pinned")
            }
            switch context {
            case .inbox:
                Button("Add to Today") { planner.addToToday(task.id) }
                    .controlSize(.small)
            case .today:
                Button("Start") { planner.startSession(task.id, mode: .standard) }
                    .controlSize(.small)
            }
            Menu {
                Button("Make this Now") { planner.pin(task.id) }
                Button("Just 5 minutes") { planner.startSession(task.id, mode: .fiveMinutes) }
                Button("Edit…") { editing = true }
                Button("Place on today") { planner.placeOnToday(task.id) }
                if context == .today {
                    Button("Move off Today") { planner.removeFromToday(task.id) }
                }
                Button("Someday") { planner.moveToSomeday(task.id) }
                Divider()
                Button("Drop") { planner.drop(task.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = true }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            TaskEditor(planner: planner, task: task)
        }
    }
}

/// Only the title is required. Everything else is optional and can stay empty.
struct TaskEditor: View {
    let planner: PlannerModel
    let task: TaskSnapshot
    @State private var title = ""
    @State private var firstStep = ""
    @State private var estimate = ""
    @State private var selectedBucket: UUID?
    @State private var newBucket = ""
    @State private var newSubtask = ""
    @Environment(\.dismiss) private var dismiss

    private var bucketSelection: Binding<UUID?> {
        Binding(get: { selectedBucket }, set: { selectedBucket = $0 })
    }

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Steps").font(.caption).foregroundStyle(.secondary)
            ForEach(planner.subtasks(for: task.id)) { item in
                Button {
                    planner.toggleSubtask(item.id)
                } label: {
                    Label(item.title, systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                TextField("Add a step", text: $newSubtask)
                Button("Add") {
                    planner.addSubtask(task.id, title: newSubtask)
                    newSubtask = ""
                }
                .disabled(newSubtask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("First step", text: $firstStep, prompt: Text("Optional — the very first physical action"))
            TextField("Estimate (minutes)", text: $estimate, prompt: Text("Optional"))
            Picker("Bucket", selection: bucketSelection) {
                Text("None").tag(UUID?.none)
                ForEach(planner.buckets) { bucket in
                    Text(bucket.name).tag(Optional(bucket.id))
                }
            }
            HStack {
                TextField("New bucket", text: $newBucket)
                Button("Add") {
                    if let bucket = planner.createBucket(newBucket) {
                        selectedBucket = bucket.id
                        newBucket = ""
                    }
                }
                .disabled(newBucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            subtaskSection
            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            title = task.title
            firstStep = task.firstStep ?? ""
            estimate = task.estimateMinutes.map(String.init) ?? ""
            selectedBucket = task.bucketID
        }
    }

    private func save() {
        let minutes = Int(estimate.trimmingCharacters(in: .whitespaces))
        planner.edit(task.id, title: title, firstStep: .some(firstStep), estimateMinutes: .some(minutes))
        if selectedBucket != task.bucketID {
            planner.assignBucket(task.id, selectedBucket)
        }
        dismiss()
    }
}
