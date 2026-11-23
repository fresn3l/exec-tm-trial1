import AppKit
import CoreGraphics
import EFCore

/// D-24: logs presence transitions only (active | idle | locked | asleep).
/// Lock/unlock are undocumented distributed notifications; if the Phase 0 check shows the sandbox
/// doesn't receive them, they simply never fire and the log falls back to sleep/wake + idle.
@MainActor
final class PresenceService {
    enum State: String { case active, idle, locked, asleep }

    private var state: State?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private let log: (State) -> Void
    private let idleThreshold: () -> TimeInterval

    init(idleThreshold: @escaping () -> TimeInterval, log: @escaping (State) -> Void) {
        self.idleThreshold = idleThreshold
        self.log = log
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        watch(ws, NSWorkspace.willSleepNotification) { .asleep }
        watch(ws, NSWorkspace.didWakeNotification) { .active }
        let dist = DistributedNotificationCenter.default()
        watch(dist, Notification.Name("com.apple.screenIsLocked")) { .locked }
        watch(dist, Notification.Name("com.apple.screenIsUnlocked")) { .active }
        set(.active)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollIdle() }
        }
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ next: @escaping @MainActor () -> State) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(next()) }
        }
        observers.append((center, token))
    }

    private func pollIdle() {
        guard state == .active || state == .idle else { return }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        set(idle >= idleThreshold() ? .idle : .active)
    }

    private func set(_ new: State) {
        guard new != state else { return }
        state = new
        log(new)
    }
}
