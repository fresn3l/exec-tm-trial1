import Foundation
import Testing
@testable import EFCore

struct SettingsTests {
    @Test func standardValuesMatchTheDecisionTable() {
        let settings = PlannerSettings.standard
        #expect(settings.dayBoundaryHour == 4)
        #expect(settings.todayCap == 3)
        #expect(settings.notificationBudget == 10)
        #expect(settings.quietHours.startMinutes == 22 * 60)
        #expect(settings.quietHours.endMinutes == 8 * 60)
        #expect(settings.defaultBufferMinutes == 10)
        #expect(settings.proposalSnapMinutes == 15)
        #expect(settings.nowLookaheadMinutes == 60)
        #expect(settings.checkInMultiplier == 1.5)
        #expect(settings.checkInNoEstimateMinutes == 45)
        #expect(settings.checkInGraceMinutes == 45)
        #expect(settings.comebackGapDays == 3)
        #expect(settings.somedayAfterDays == 30)
        #expect(settings.estimatorMinSamples == 5)
        #expect(settings.estimatorWindow == 20)
        #expect(settings.estimatorClamp.lower == 0.5)
        #expect(settings.estimatorClamp.upper == 3.0)
        #expect(settings.idleThresholdMinutes == 5)
        #expect(settings.calendarModes.isEmpty)
        #expect(settings.energyWindows.isEmpty)
    }

    @Test func settingsRoundTripThroughJSON() throws {
        var settings = PlannerSettings.standard
        settings.calendarModes = ["work": CalendarModeOverride(mode: .hidden, title: "Work")]
        settings.todayCap = 2
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PlannerSettings.self, from: data)
        #expect(decoded == settings)
    }
}
