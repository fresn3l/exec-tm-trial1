import EFCore
import Foundation

public struct SettingsStore {
    private let defaults: UserDefaults
    public static let key = "PlannerSettings"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func appGroup() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: ExecFnAppGroup.identifier) ?? .standard)
    }

    public func load() -> PlannerSettings {
        guard let data = defaults.data(forKey: Self.key) else { return .standard }
        return (try? JSONDecoder().decode(PlannerSettings.self, from: data)) ?? .standard
    }

    public func save(_ settings: PlannerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
