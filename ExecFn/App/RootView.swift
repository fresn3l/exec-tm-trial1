import EFCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @State private var section: Section? = .today

    enum Section: Hashable { case today, inbox, calendar, someday, routines }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Today", systemImage: "sun.max").tag(Section.today)
                Label("Inbox", systemImage: "tray").tag(Section.inbox)
                Label("Calendar", systemImage: "calendar").tag(Section.calendar)
                Label("Someday", systemImage: "archivebox").tag(Section.someday)
                Label("Routines", systemImage: "repeat").tag(Section.routines)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                if let problem = model.planner.problem {
                    Text(problem)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary)
                }
                if let block = model.planner.passedBlock, let task = model.planner.task(block.taskID) {
                    PassedTimePrompt(planner: model.planner, block: block, task: task)
                }
                switch section ?? .today {
                case .today: TodayScreen(planner: model.planner)
                case .inbox: InboxScreen(planner: model.planner)
                case .calendar: DayScreen(model: model)
                case .someday: SomedayScreen(planner: model.planner)
                case .routines: RoutinesScreen(planner: model.planner)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .task { await model.start() }
        .sheet(item: Binding(get: { model.planner.capPrompt }, set: { model.planner.capPrompt = $0 })) { prompt in
            CapPromptSheet(planner: model.planner, prompt: prompt)
        }
        .overlay(alignment: .bottom) { CompletionToast(planner: model.planner) }
    }
}

/// D-07: "Today already has 3. Swap one?" — a suggestion with an override.
struct CapPromptSheet: View {
    let planner: PlannerModel
    let prompt: PlannerModel.CapPrompt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today already has \(prompt.current.count). Swap one?")
                .font(.title3.weight(.semibold))
            Text("Adding “\(prompt.task.title)”. Fewer things on Today makes the next one easier to pick.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(prompt.current) { must in
                    Button {
                        planner.resolveCapPrompt(swapOut: must.id)
                        dismiss()
                    } label: {
                        Label("Move “\(must.title)” off Today", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.link)
                }
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    planner.capPrompt = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add anyway") {
                    planner.resolveCapPrompt(swapOut: nil)
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// D-21: a short, quiet acknowledgement. No sound by default.
struct CompletionToast: View {
    let planner: PlannerModel
    @State private var visible = false

    var body: some View {
        Group {
            if visible, let title = planner.lastCelebratedTitle {
                Label("Done: \(title)", systemImage: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: planner.celebration)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: planner.celebration) {
            withAnimation(.spring(duration: 0.35)) { visible = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.3)) { visible = false }
            }
        }
    }
}
