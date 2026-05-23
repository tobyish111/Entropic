import Foundation
import Testing
@testable import Entropic

struct EntropicTests {
    @Test func entropyCalculationUsesActiveAndBasalHeat() {
        let entropy = EntropyCalculator.entropyKJPerK(activeKcal: 100,
                                                      basalKcal: 50,
                                                      ambientCelsius: 22,
                                                      activeHeatFraction: 0.85,
                                                      basalHeatFraction: 1.0)
        let expected = ((100 * 4.184 * 0.85) + (50 * 4.184)) / 295.15
        #expect(entropy.isApproximately(expected))
    }

    @Test func entropyCalculationClampsNegativeEnergyToZero() {
        let entropy = EntropyCalculator.entropyKJPerK(activeKcal: -100,
                                                      basalKcal: -50,
                                                      ambientCelsius: 22,
                                                      activeHeatFraction: 1,
                                                      basalHeatFraction: 1)
        #expect(entropy == 0)
    }

    @Test func entropyCalculationClampsHeatFractions() {
        let entropy = EntropyCalculator.entropyKJPerK(activeKcal: 100,
                                                      basalKcal: 100,
                                                      ambientCelsius: 22,
                                                      activeHeatFraction: 2,
                                                      basalHeatFraction: -1)
        let expected = (100 * 4.184) / 295.15
        #expect(entropy.isApproximately(expected))
    }

    @Test func entropyCalculationUsesMinimumKelvinForExtremeTemperature() {
        let entropy = EntropyCalculator.entropyKJPerK(activeKcal: 1,
                                                      basalKcal: 0,
                                                      ambientCelsius: -400,
                                                      activeHeatFraction: 1,
                                                      basalHeatFraction: 1)
        #expect(entropy.isApproximately(4.184))
    }

    @Test func entropyFormattingHandlesNilAndNonFiniteValues() {
        #expect(EntropyCalculator.formatEntropy(nil) == "-- kJ/K")
        #expect(EntropyCalculator.formatEntropy(.nan) == "-- kJ/K")
        #expect(EntropyCalculator.formatEntropy(.infinity) == "-- kJ/K")
    }

    @Test func entropyFormattingUsesOneDecimalBelowOneThousand() {
        #expect(EntropyCalculator.formatEntropy(12.34) == "12.3 kJ/K")
    }

    @Test func entropyFormattingUsesNoDecimalsAtOrAboveOneThousand() {
        #expect(EntropyCalculator.formatEntropy(1200.4) == "1200 kJ/K")
    }

    @Test func energyFormattingHandlesMissingAndInvalidValues() {
        #expect(EntropyCalculator.formatEnergyKcal(nil) == "-- kcal")
        #expect(EntropyCalculator.formatEnergyKcal(.nan) == "-- kcal")
        #expect(EntropyCalculator.formatEnergyKcal(.infinity) == "-- kcal")
    }

    @Test func energyFormattingRoundsToNearestKcal() {
        #expect(EntropyCalculator.formatEnergyKcal(99.6) == "100 kcal")
    }

    @MainActor
    @Test func dashboardStartWithDeniedHealthSetsUnavailableWithoutRefreshing() async {
        let health = FakeEntropicHealthProvider(authorizationResult: false)
        let viewModel = EntropicDashboardViewModel(health: health)

        await viewModel.start()

        #expect(viewModel.status == "Health unavailable")
        #expect(health.energyTotalsCalls == 0)
        #expect(viewModel.entropyTodayKJPerK == nil)
    }

    @MainActor
    @Test func dashboardStartWithAuthorizationErrorSetsUnavailable() async {
        let health = FakeEntropicHealthProvider(authorizationError: FakeError.expected)
        let viewModel = EntropicDashboardViewModel(health: health)

        await viewModel.start()

        #expect(viewModel.status == "Health unavailable")
        #expect(viewModel.entropyTodayKJPerK == nil)
    }

    @MainActor
    @Test func dashboardRefreshPopulatesCurrentTotalsAndTrends() async {
        let dailyPoints = makeTrendPoints([1, 2, 3])
        let hourlyPoints = makeTrendPoints([0.5, 4, 2])
        let health = FakeEntropicHealthProvider(today: EnergyTotals(activeKcal: 120, basalKcal: 80),
                                                hourlyPoints: hourlyPoints,
                                                dailyPoints: dailyPoints)
        let viewModel = EntropicDashboardViewModel(health: health, ambientCelsius: 22)

        await viewModel.refresh()

        #expect(viewModel.status == "Live")
        #expect(viewModel.activeEnergyKcal == 120)
        #expect(viewModel.basalEnergyKcal == 80)
        #expect(viewModel.hourlyPoints.map(\.entropyKJPerK) == [0.5, 4, 2])
        #expect(viewModel.dailyPoints.map(\.entropyKJPerK) == [1, 2, 3])
        #expect(viewModel.entropyTodayKJPerK?.isApproximately(((120 * 4.184 * 0.85) + (80 * 4.184)) / 295.15) == true)
        #expect(viewModel.lastUpdated != nil)
    }

    @MainActor
    @Test func dashboardRefreshFailureSetsFailureStatusAndLeavesCurrentValuesUnset() async {
        let health = FakeEntropicHealthProvider(refreshError: FakeError.expected)
        let viewModel = EntropicDashboardViewModel(health: health)

        await viewModel.refresh()

        #expect(viewModel.status == "Refresh failed")
        #expect(viewModel.entropyTodayKJPerK == nil)
        #expect(viewModel.hourlyPoints.isEmpty)
        #expect(viewModel.dailyPoints.isEmpty)
    }

    @MainActor
    @Test func dashboardTrendSummariesHandleEmptyData() {
        let viewModel = EntropicDashboardViewModel(health: FakeEntropicHealthProvider())

        #expect(viewModel.fourteenDayAverageFormatted == "-- kJ/K")
        #expect(viewModel.trendDirection == "Building trend")
        #expect(viewModel.peakHourFormatted == "--")
    }

    @MainActor
    @Test func dashboardTrendDirectionDetectsRisingFallingAndStable() async {
        let rising = EntropicDashboardViewModel(health: FakeEntropicHealthProvider(dailyPoints: makeTrendPoints([1, 3])))
        await rising.refresh()
        #expect(rising.trendDirection == "Rising")

        let falling = EntropicDashboardViewModel(health: FakeEntropicHealthProvider(dailyPoints: makeTrendPoints([3, 1])))
        await falling.refresh()
        #expect(falling.trendDirection == "Falling")

        let stable = EntropicDashboardViewModel(health: FakeEntropicHealthProvider(dailyPoints: makeTrendPoints([3, 3.05])))
        await stable.refresh()
        #expect(stable.trendDirection == "Stable")
    }

    @MainActor
    @Test func dashboardAverageIgnoresNonFiniteTrendPoints() async {
        let viewModel = EntropicDashboardViewModel(health: FakeEntropicHealthProvider(dailyPoints: makeTrendPoints([1, .nan, 3, .infinity])))

        await viewModel.refresh()

        #expect(viewModel.fourteenDayAverageFormatted == "2.0 kJ/K")
    }

    @Test func liveWatchSnapshotFormatsValues() {
        let snapshot = LiveWatchWorkoutSnapshot(entropyKJPerK: 12.34,
                                                activeKcal: 99.6,
                                                basalKcal: 50.2,
                                                heartRateBPM: 141.7,
                                                elapsedSeconds: 125,
                                                ambientCelsius: 21.6,
                                                state: "Live",
                                                timestamp: Date())

        #expect(snapshot.entropyFormatted == "12.3 kJ/K")
        #expect(snapshot.activeEnergyFormatted == "100 kcal")
        #expect(snapshot.basalEnergyFormatted == "50 kcal")
        #expect(snapshot.heartRateFormatted == "142 bpm")
        #expect(snapshot.elapsedFormatted == "02:05")
        #expect(snapshot.ambientFormatted == "22 °C")
        #expect(snapshot.isRecent)
    }

    @Test func liveWatchSnapshotWithoutHeartRateUsesPlaceholder() {
        let snapshot = LiveWatchWorkoutSnapshot(entropyKJPerK: 1,
                                                activeKcal: 1,
                                                basalKcal: 1,
                                                heartRateBPM: nil,
                                                elapsedSeconds: 1,
                                                ambientCelsius: 22,
                                                state: "Live",
                                                timestamp: Date())

        #expect(snapshot.heartRateFormatted == "-- bpm")
    }

    @Test func liveWatchSnapshotIsNotRecentWhenStaleOrEnded() {
        let stale = LiveWatchWorkoutSnapshot(entropyKJPerK: 1,
                                             activeKcal: 1,
                                             basalKcal: 1,
                                             heartRateBPM: nil,
                                             elapsedSeconds: 1,
                                             ambientCelsius: 22,
                                             state: "Live",
                                             timestamp: Date(timeIntervalSinceNow: -120))
        let ended = LiveWatchWorkoutSnapshot(entropyKJPerK: 1,
                                             activeKcal: 1,
                                             basalKcal: 1,
                                             heartRateBPM: nil,
                                             elapsedSeconds: 1,
                                             ambientCelsius: 22,
                                             state: "Ended",
                                             timestamp: Date())

        #expect(!stale.isRecent)
        #expect(!ended.isRecent)
    }
}

private final class FakeEntropicHealthProvider: EntropicHealthProviding {
    var authorizationResult: Bool
    var authorizationError: Error?
    var refreshError: Error?
    var today: EnergyTotals
    var hourlyPoints: [EntropyTrendPoint]
    var dailyPoints: [EntropyTrendPoint]
    var energyTotalsCalls = 0

    init(authorizationResult: Bool = true,
         authorizationError: Error? = nil,
         refreshError: Error? = nil,
         today: EnergyTotals = .zero,
         hourlyPoints: [EntropyTrendPoint] = [],
         dailyPoints: [EntropyTrendPoint] = []) {
        self.authorizationResult = authorizationResult
        self.authorizationError = authorizationError
        self.refreshError = refreshError
        self.today = today
        self.hourlyPoints = hourlyPoints
        self.dailyPoints = dailyPoints
    }

    func requestAuthorization() async throws -> Bool {
        if let authorizationError { throw authorizationError }
        return authorizationResult
    }

    func energyTotals(from start: Date, to end: Date) async throws -> EnergyTotals {
        energyTotalsCalls += 1
        if let refreshError { throw refreshError }
        return today
    }

    func dailyEnergyTotals(days: Int, endingAt endDate: Date) async throws -> [EntropyTrendPoint] {
        if let refreshError { throw refreshError }
        return dailyPoints
    }

    func hourlyEnergyTotals(hours: Int, endingAt endDate: Date) async throws -> [EntropyTrendPoint] {
        if let refreshError { throw refreshError }
        return hourlyPoints
    }
}

private enum FakeError: Error {
    case expected
}

private func makeTrendPoints(_ values: [Double]) -> [EntropyTrendPoint] {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return values.enumerated().map { index, entropy in
        EntropyTrendPoint(date: start.addingTimeInterval(Double(index) * 3600),
                          activeKcal: Double(index),
                          basalKcal: Double(index),
                          entropyKJPerK: entropy)
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
