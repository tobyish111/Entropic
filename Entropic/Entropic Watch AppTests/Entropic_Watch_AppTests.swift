import Foundation
import Testing
@testable import Entropic_Watch_App

struct Entropic_Watch_AppTests {
    @Test func entropyCalculationUsesActiveAndBasalHeat() {
        let entropy = EntropyCalculator.entropyKJPerK(activeKcal: 100,
                                                      basalKcal: 50,
                                                      ambientCelsius: 22,
                                                      activeHeatFraction: 0.85,
                                                      basalHeatFraction: 1.0)
        let expected = ((100 * 4.184 * 0.85) + (50 * 4.184)) / 295.15
        #expect(entropy.isApproximately(expected))
    }

    @Test func entropyCalculationLegacySingleEnergyPathMatchesActiveOnlyPath() {
        let legacy = EntropyCalculator.entropyKJPerK(energyKcal: 100,
                                                     ambientCelsius: 22,
                                                     heatFraction: 0.8)
        let activeOnly = EntropyCalculator.entropyKJPerK(activeKcal: 100,
                                                         basalKcal: 0,
                                                         ambientCelsius: 22,
                                                         activeHeatFraction: 0.8,
                                                         basalHeatFraction: 0.8)
        #expect(legacy.isApproximately(activeOnly))
    }

    @Test func entropyCalculationClampsNegativeEnergyAndFractions() {
        let negativeEnergy = EntropyCalculator.entropyKJPerK(activeKcal: -100,
                                                             basalKcal: -50,
                                                             ambientCelsius: 22,
                                                             activeHeatFraction: 1,
                                                             basalHeatFraction: 1)
        #expect(negativeEnergy == 0)

        let clampedFractions = EntropyCalculator.entropyKJPerK(activeKcal: 100,
                                                               basalKcal: 100,
                                                               ambientCelsius: 22,
                                                               activeHeatFraction: 2,
                                                               basalHeatFraction: -1)
        let expected = (100 * 4.184) / 295.15
        #expect(clampedFractions.isApproximately(expected))
    }

    @Test func entropyCalculationUsesMinimumKelvinForExtremeTemperature() {
        let entropy = EntropyCalculator.entropyKJPerK(activeKcal: 1,
                                                      basalKcal: 0,
                                                      ambientCelsius: -400,
                                                      activeHeatFraction: 1,
                                                      basalHeatFraction: 1)
        #expect(entropy.isApproximately(4.184))
    }

    @Test func calculatorFormattingHandlesNormalMissingAndInvalidValues() {
        #expect(EntropyCalculator.formatEntropy(12.34) == "12.3 kJ/K")
        #expect(EntropyCalculator.formatEntropy(1200.4) == "1200 kJ/K")
        #expect(EntropyCalculator.formatEntropy(.nan) == "— kJ/K")
        #expect(EntropyCalculator.formatEntropy(.infinity) == "— kJ/K")
        #expect(EntropyCalculator.formatEnergyKcal(nil) == "— kcal")
        #expect(EntropyCalculator.formatEnergyKcal(.nan) == "— kcal")
        #expect(EntropyCalculator.formatEnergyKcal(99.6) == "100 kcal")
    }

    @MainActor
    @Test func viewModelUsesDefaultsWhenNoSettingsExist() {
        clearEntropyDefaults()

        let viewModel = EntropyViewModel(health: FakeHealthProvider(), weather: FakeWeatherProvider())

        #expect(viewModel.ambientCelsius == 22)
        #expect(viewModel.heatFraction == 0.85)
        #expect(viewModel.basalHeatFraction == 1.0)
        #expect(viewModel.entropyTodayFormatted == "0.0 kJ/K")
        #expect(viewModel.activeEnergyFormatted == "— kcal")
        #expect(viewModel.basalEnergyFormatted == "— kcal")
        #expect(viewModel.lastUpdatedFormatted == "Not updated")
    }

    @MainActor
    @Test func viewModelLoadsPersistedSettings() {
        UserDefaults.standard.set(18.0, forKey: "ambient.celsius")
        UserDefaults.standard.set(0.7, forKey: "heat.fraction")
        UserDefaults.standard.set(0.9, forKey: "heat.fraction.basal")

        let viewModel = EntropyViewModel(health: FakeHealthProvider(), weather: FakeWeatherProvider())

        #expect(viewModel.ambientCelsius == 18)
        #expect(viewModel.heatFraction == 0.7)
        #expect(viewModel.basalHeatFraction == 0.9)
    }

    @MainActor
    @Test func viewModelRefreshUsesLiveWeatherAndHealthTotals() async {
        clearEntropyDefaults()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let health = FakeHealthProvider(activeKcal: 120, basalKcal: 80)
        let weather = FakeWeatherProvider(ambientCelsius: 10)
        let viewModel = EntropyViewModel(health: health, weather: weather)

        await viewModel.refreshToday(now: now)

        let expected = EntropyCalculator.entropyKJPerK(activeKcal: 120,
                                                       basalKcal: 80,
                                                       ambientCelsius: 10,
                                                       activeHeatFraction: 0.85,
                                                       basalHeatFraction: 1.0)
        #expect(viewModel.ambientCelsius == 10)
        #expect(viewModel.weatherStatus == "Live weather")
        #expect(viewModel.activeEnergyKcal == 120)
        #expect(viewModel.basalEnergyKcal == 80)
        #expect(viewModel.entropyTodayKJPerK?.isApproximately(expected) == true)
        #expect(viewModel.lastUpdated == now)
        #expect(viewModel.healthStatus == nil)
    }

    @MainActor
    @Test func viewModelRefreshCanSkipWeatherUpdate() async {
        clearEntropyDefaults()
        let weather = FakeWeatherProvider(ambientCelsius: 5)
        let viewModel = EntropyViewModel(health: FakeHealthProvider(activeKcal: 10, basalKcal: 0),
                                         weather: weather,
                                         ambientCelsius: 30)

        await viewModel.refreshToday(updateWeather: false)

        #expect(viewModel.ambientCelsius == 30)
        #expect(weather.callCount == 0)
    }

    @MainActor
    @Test func viewModelWeatherFailureFallsBackToManualAmbient() async {
        clearEntropyDefaults()
        let viewModel = EntropyViewModel(health: FakeHealthProvider(activeKcal: 10, basalKcal: 10),
                                         weather: FakeWeatherProvider(error: FakeError.expected),
                                         ambientCelsius: 24)

        await viewModel.refreshToday()

        #expect(viewModel.ambientCelsius == 24)
        #expect(viewModel.weatherStatus == "Manual ambient")
        #expect(viewModel.entropyTodayKJPerK != nil)
    }

    @MainActor
    @Test func viewModelHealthQueryFailureClearsOutputsAndSetsStatus() async {
        clearEntropyDefaults()
        let viewModel = EntropyViewModel(health: FakeHealthProvider(queryError: FakeError.expected),
                                         weather: FakeWeatherProvider(ambientCelsius: 15))

        await viewModel.refreshToday()

        #expect(viewModel.healthStatus == "Health unavailable")
        #expect(viewModel.activeEnergyKcal == nil)
        #expect(viewModel.basalEnergyKcal == nil)
        #expect(viewModel.entropyTodayKJPerK == nil)
    }

    @MainActor
    @Test func ensureAuthorizedRefreshesWhenAuthorized() async {
        clearEntropyDefaults()
        let health = FakeHealthProvider(authorizationResult: true, activeKcal: 10, basalKcal: 5)
        let viewModel = EntropyViewModel(health: health, weather: FakeWeatherProvider(ambientCelsius: 20))

        await viewModel.ensureAuthorizedAndRefresh()

        #expect(health.authorizationCalls == 1)
        #expect(viewModel.healthStatus == nil)
        #expect(viewModel.entropyTodayKJPerK != nil)
    }

    @MainActor
    @Test func ensureAuthorizedDoesNotQueryHealthWhenAuthorizationDenied() async {
        clearEntropyDefaults()
        let health = FakeHealthProvider(authorizationResult: false, activeKcal: 10, basalKcal: 5)
        let weather = FakeWeatherProvider(ambientCelsius: 20)
        let viewModel = EntropyViewModel(health: health, weather: weather)

        await viewModel.ensureAuthorizedAndRefresh()

        #expect(viewModel.healthStatus == "Health unavailable")
        #expect(health.activeCalls == 0)
        #expect(health.basalCalls == 0)
        #expect(weather.callCount == 1)
        #expect(viewModel.entropyTodayKJPerK == nil)
    }

    @MainActor
    @Test func ensureAuthorizedHandlesAuthorizationError() async {
        clearEntropyDefaults()
        let health = FakeHealthProvider(authorizationError: FakeError.expected)
        let weather = FakeWeatherProvider(ambientCelsius: 20)
        let viewModel = EntropyViewModel(health: health, weather: weather)

        await viewModel.ensureAuthorizedAndRefresh()

        #expect(viewModel.healthStatus == "Health unavailable")
        #expect(weather.callCount == 1)
    }

    @MainActor
    @Test func liveWorkoutManagerDerivedFormattingAndEntropyAreStable() {
        let manager = LiveWorkoutManager()

        #expect(!manager.hasActiveWorkout)
        #expect(manager.activeEnergyFormatted == "0 kcal")
        #expect(manager.basalEnergyFormatted == "0 kcal")
        #expect(manager.heartRateFormatted == "-- bpm")
        #expect(manager.elapsedFormatted == "00:00")
        #expect(manager.entropyKJPerK(ambientCelsius: 22, activeHeatFraction: 0.85, basalHeatFraction: 1) == 0)
    }

    @MainActor
    @Test func appleWorkoutFollowerInitialStateIsIdleAndZeroed() {
        let follower = AppleWorkoutFollower(health: FakeHealthProvider())

        #expect(!follower.isFollowing)
        #expect(follower.status == "Apple Idle")
        #expect(follower.activeEnergyFormatted == "0 kcal")
        #expect(follower.basalEnergyFormatted == "0 kcal")
        #expect(follower.elapsedFormatted == "00:00")
        #expect(follower.entropyKJPerK(ambientCelsius: 22, activeHeatFraction: 0.85, basalHeatFraction: 1) == 0)
    }
}

private final class FakeHealthProvider: HealthProviding {
    var authorizationResult: Bool
    var authorizationError: Error?
    var queryError: Error?
    var activeKcal: Double
    var basalKcal: Double
    var authorizationCalls = 0
    var activeCalls = 0
    var basalCalls = 0

    init(authorizationResult: Bool = true,
         authorizationError: Error? = nil,
         queryError: Error? = nil,
         activeKcal: Double = 0,
         basalKcal: Double = 0) {
        self.authorizationResult = authorizationResult
        self.authorizationError = authorizationError
        self.queryError = queryError
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
    }

    func requestAuthorization() async throws -> Bool {
        authorizationCalls += 1
        if let authorizationError { throw authorizationError }
        return authorizationResult
    }

    func activeEnergyKcal(from start: Date, to end: Date) async throws -> Double {
        activeCalls += 1
        if let queryError { throw queryError }
        return activeKcal
    }

    func basalEnergyKcal(from start: Date, to end: Date) async throws -> Double {
        basalCalls += 1
        if let queryError { throw queryError }
        return basalKcal
    }
}

private final class FakeWeatherProvider: WeatherProviding {
    var ambientCelsius: Double
    var error: Error?
    var callCount = 0

    init(ambientCelsius: Double = 22, error: Error? = nil) {
        self.ambientCelsius = ambientCelsius
        self.error = error
    }

    func ambientCelsius() async throws -> Double {
        callCount += 1
        if let error { throw error }
        return ambientCelsius
    }
}

private enum FakeError: Error {
    case expected
}

private func clearEntropyDefaults() {
    UserDefaults.standard.removeObject(forKey: "ambient.celsius")
    UserDefaults.standard.removeObject(forKey: "heat.fraction")
    UserDefaults.standard.removeObject(forKey: "heat.fraction.basal")
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
