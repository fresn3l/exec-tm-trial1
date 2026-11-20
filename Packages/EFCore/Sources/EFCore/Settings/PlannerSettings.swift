import Foundation

public enum CalendarMode: String, Codable, Sendable, Hashable, CaseIterable {
    case hidden
    case visible
    case busy
}

public struct CalendarModeOverride: Hashable, Codable, Sendable {
    public var mode: CalendarMode
    public var title: String

    public init(mode: CalendarMode, title: String) {
        self.mode = mode
        self.title = title
    }
}

public struct QuietHours: Hashable, Codable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int = 22 * 60, endMinutes: Int = 8 * 60) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }
}

public struct EstimatorClamp: Hashable, Codable, Sendable {
    public var lower: Double
    public var upper: Double

    public init(lower: Double = 0.5, upper: Double = 3.0) {
        self.lower = lower
        self.upper = upper
    }
}

public struct EnergyWindow: Hashable, Codable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int
    public var energy: TaskEnergy

    public init(startMinutes: Int, endMinutes: Int, energy: TaskEnergy) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.energy = energy
    }
}

/// Every tunable a pure function is allowed to read. The UI writes it; nothing else does.
public struct PlannerSettings: Hashable, Codable, Sendable {
    public var dayBoundaryHour: Int
    public var todayCap: Int
    public var notificationBudget: Int
    public var quietHours: QuietHours
    public var defaultBufferMinutes: Int
    public var proposalSnapMinutes: Int
    public var nowLookaheadMinutes: Int
    public var checkInMultiplier: Double
    public var checkInNoEstimateMinutes: Int
    public var checkInGraceMinutes: Int
    public var comebackGapDays: Int
    public var somedayAfterDays: Int
    public var estimatorMinSamples: Int
    public var estimatorWindow: Int
    public var estimatorClamp: EstimatorClamp
    public var idleThresholdMinutes: Int
    public var calendarModes: [String: CalendarModeOverride]
    public var energyWindows: [EnergyWindow]

    public init(
        dayBoundaryHour: Int = 4,
        todayCap: Int = 3,
        notificationBudget: Int = 10,
        quietHours: QuietHours = QuietHours(),
        defaultBufferMinutes: Int = 10,
        proposalSnapMinutes: Int = 15,
        nowLookaheadMinutes: Int = 60,
        checkInMultiplier: Double = 1.5,
        checkInNoEstimateMinutes: Int = 45,
        checkInGraceMinutes: Int = 45,
        comebackGapDays: Int = 3,
        somedayAfterDays: Int = 30,
        estimatorMinSamples: Int = 5,
        estimatorWindow: Int = 20,
        estimatorClamp: EstimatorClamp = EstimatorClamp(),
        idleThresholdMinutes: Int = 5,
        calendarModes: [String: CalendarModeOverride] = [:],
        energyWindows: [EnergyWindow] = []
    ) {
        self.dayBoundaryHour = dayBoundaryHour
        self.todayCap = todayCap
        self.notificationBudget = notificationBudget
        self.quietHours = quietHours
        self.defaultBufferMinutes = defaultBufferMinutes
        self.proposalSnapMinutes = proposalSnapMinutes
        self.nowLookaheadMinutes = nowLookaheadMinutes
        self.checkInMultiplier = checkInMultiplier
        self.checkInNoEstimateMinutes = checkInNoEstimateMinutes
        self.checkInGraceMinutes = checkInGraceMinutes
        self.comebackGapDays = comebackGapDays
        self.somedayAfterDays = somedayAfterDays
        self.estimatorMinSamples = estimatorMinSamples
        self.estimatorWindow = estimatorWindow
        self.estimatorClamp = estimatorClamp
        self.idleThresholdMinutes = idleThresholdMinutes
        self.calendarModes = calendarModes
        self.energyWindows = energyWindows
    }

    public static let standard = PlannerSettings()
}
