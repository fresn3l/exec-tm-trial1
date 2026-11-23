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
        #expect(settings.fiveMinuteStartMinutes == 5)
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

    /// Settings saved by Phase 1 have no `fiveMinuteStartMinutes`. They must still load,
    /// and the saved calendar modes must survive (D-04).
    @Test func phaseOneSettingsStillDecode() throws {
        let phaseOne = """
        {"dayBoundaryHour":5,"todayCap":2,"notificationBudget":10,
         "quietHours":{"startMinutes":1320,"endMinutes":480},"defaultBufferMinutes":10,
         "proposalSnapMinutes":15,"nowLookaheadMinutes":60,"checkInMultiplier":1.5,
         "checkInNoEstimateMinutes":45,"checkInGraceMinutes":45,"comebackGapDays":3,
         "somedayAfterDays":30,"estimatorMinSamples":5,"estimatorWindow":20,
         "estimatorClamp":{"lower":0.5,"upper":3},"idleThresholdMinutes":5,
         "calendarModes":{"cal-1":{"mode":"hidden","title":"Birthdays"}},"energyWindows":[]}
        """
        let decoded = try JSONDecoder().decode(PlannerSettings.self, from: Data(phaseOne.utf8))
        #expect(decoded.dayBoundaryHour == 5)
        #expect(decoded.todayCap == 2)
        #expect(decoded.fiveMinuteStartMinutes == 5)
        #expect(decoded.calendarModes["cal-1"] == CalendarModeOverride(mode: .hidden, title: "Birthdays"))
    }

    @Test func aBadFieldFallsBackWithoutLosingTheRest() throws {
        let json = #"{"todayCap":"three","calendarModes":{"w":{"mode":"busy","title":"Work"}}}"#
        let decoded = try JSONDecoder().decode(PlannerSettings.self, from: Data(json.utf8))
        #expect(decoded.todayCap == 3)
        #expect(decoded.calendarModes["w"]?.mode == .busy)
    }
}
