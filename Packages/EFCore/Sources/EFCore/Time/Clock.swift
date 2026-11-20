import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }
    public var timeZone: TimeZone { .current }
}

public struct FixedClock: Clock {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}

extension Clock {
    public func boundary(hour: Int) -> DayBoundary {
        DayBoundary(hour: hour, timeZone: timeZone)
    }
}
