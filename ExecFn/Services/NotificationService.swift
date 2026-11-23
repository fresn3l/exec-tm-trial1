import EFCore
import Foundation
@preconcurrency import UserNotifications

/// The only code that talks to `UNUserNotificationCenter` (guardrail).
/// Phase 2: the D-14 / D-27 check-in category only. The full planner arrives in Phase 4a.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let checkInCategory = "checkIn"
    static let checkInID = "execfn.checkIn"
    private enum Action: String { case keepGoing, done, stop }

    private let center = UNUserNotificationCenter.current()
    private weak var planner: PlannerModel?

    func start(planner: PlannerModel) {
        self.planner = planner
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.keepGoing.rawValue, title: String(localized: "Keep going")),
            UNNotificationAction(identifier: Action.done.rawValue, title: String(localized: "Done")),
            UNNotificationAction(identifier: Action.stop.rawValue, title: String(localized: "Stop")),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.checkInCategory, actions: actions, intentIdentifiers: []),
        ])
    }

    /// Reschedules the single pending check-in from the session's current state.
    func sessionChanged(_ session: SessionSnapshot?, task: TaskSnapshot?, settings: PlannerSettings) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.checkInID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.checkInID])
        guard let session, session.isOpen else { return }
        let fire = SessionRules.nextCheckIn(session, estimateMinutes: task?.estimateMinutes, settings: settings)
        let content = UNMutableNotificationContent()
        let fiveMinutes = SessionRules.isFiveMinutePrompt(session)
        content.title = fiveMinutes ? String(localized: "Five minutes in. Keep going?") : String(localized: "Still on this?")
        content.body = task?.title ?? ""
        content.categoryIdentifier = Self.checkInCategory
        content.interruptionLevel = .active
        let delay = max(1, fire.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: Self.checkInID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            guard granted else { return }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { planner?.noteCheckInShown() }
        return [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.actionIdentifier
        await MainActor.run {
            switch Action(rawValue: id) {
            case .keepGoing: planner?.answerCheckIn(.keepGoing)
            case .done: planner?.answerCheckIn(.done)
            case .stop: planner?.answerCheckIn(.stop)
            case nil: break   // tapped the banner: just opens the app
            }
            planner?.log(.notificationActed, task: planner?.openSession?.taskID, ["category": Self.checkInCategory, "action": id])
        }
    }
}
