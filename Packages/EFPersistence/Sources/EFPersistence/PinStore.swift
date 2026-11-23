import Foundation

/// D-08: the single pinned task. App state, not a setting, so it has its own key (D-04).
/// Cleared by Done, Drop, Unpin, and rollover; survives relaunch within the day.
public struct PinStore {
    private let defaults: UserDefaults
    public static let key = "PinnedTaskID"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func appGroup() -> PinStore {
        PinStore(defaults: UserDefaults(suiteName: ExecFnAppGroup.identifier) ?? .standard)
    }

    public var pinnedTaskID: UUID? {
        defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
    }

    public func pin(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
