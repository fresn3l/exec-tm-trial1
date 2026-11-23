import AppKit
import EFCore
import SwiftUI

/// Small always-on-top timer while a session runs. Seconds live here, not in the menu bar (D-25).
@MainActor
final class FocusTimerController {
    private var panel: NSPanel?
    private let planner: PlannerModel

    init(planner: PlannerModel) {
        self.planner = planner
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 24, y: f.maxY - panel.frame.height - 24))
            }
            panel.orderFrontRegardless()
        }
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: FocusTimerView(planner: planner))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        return panel
    }
}

struct FocusTimerView: View {
    let planner: PlannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = planner.openSession, let task = planner.sessionTask {
                Text(task.title).font(.headline).lineLimit(2)
                if let step = task.firstStep {
                    Text(step).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                TimelineView(.periodic(from: session.start, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timerText(session: session, now: context.date))
                            .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                        if let estimate = task.estimateMinutes, estimate > 0 {
                            ProgressView(
                                value: min(context.date.timeIntervalSince(session.start), Double(estimate * 60)),
                                total: Double(estimate * 60)
                            )
                            .tint(.secondary)
                        }
                    }
                }
                if planner.isCheckInDue {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(planner.isFiveMinutePrompt ? "Five minutes in. Keep going?" : "Still on this?")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            Button(planner.isFiveMinutePrompt ? "Keep going" : "Yes") { planner.answerCheckIn(.keepGoing) }
                                .buttonStyle(.borderedProminent)
                            Button("Done") { planner.answerCheckIn(.done) }
                            Button(planner.isFiveMinutePrompt ? "Stop here" : "Stop") { planner.answerCheckIn(.stop) }
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Button("Stop") { planner.stopSession() }
                        Spacer()
                        Button("Done") { planner.complete(task.id) }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                }
            } else {
                Text("No session running").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
