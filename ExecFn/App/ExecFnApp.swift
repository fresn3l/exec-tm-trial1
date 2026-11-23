import AppKit
import EFCore
import SwiftUI

@main
struct ExecFnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ExecFn", id: "main") {
            RootView(model: delegate.model)
        }
        .defaultSize(width: 980, height: 760)

        MenuBarExtra {
            MenuBarContent(
                model: delegate.model,
                openCapture: { delegate.capture.toggle() },
                showTimer: { delegate.timer.show() }
            )
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsScreen(model: delegate.model)
        }
    }
}

/// Owns the long-lived services so they run even when the main window is closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private(set) lazy var capture = CapturePanelController { [unowned self] text in
        model.planner.capture(text, source: .hotkey)
    }
    private(set) lazy var timer = FocusTimerController(planner: model.planner)
    private let hotkey = HotkeyService()
    private let notifications = NotificationService()
    private var presence: PresenceService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let planner = model.planner!
        notifications.start(planner: planner)
        planner.onSessionChange = { [unowned self] session, task in
            notifications.sessionChanged(session, task: task, settings: model.settings)
            if session != nil { timer.show() } else { timer.hide() }
        }
        if !hotkey.register({ [unowned self] in capture.toggle() }) {
            planner.problem = String(localized: "⌃⌥Space is taken by another app, so the capture shortcut is off.")
        }
        presence = PresenceService(
            idleThreshold: { [unowned self] in TimeInterval(model.settings.idleThresholdMinutes * 60) },
            log: { state in planner.log(.presence, task: nil, ["state": state.rawValue]) }
        )
        presence?.start()
        Task {
            await model.start()
            // A session that survived a relaunch gets its check-in and timer back.
            planner.onSessionChange?(planner.openSession, planner.sessionTask)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.planner.appWillTerminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
