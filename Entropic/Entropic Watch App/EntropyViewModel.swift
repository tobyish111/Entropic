import Foundation
import SwiftUI

@MainActor
final class EntropyViewModel: ObservableObject {
    // Dependencies
    private let health: HealthProviding
    private let weather: WeatherProviding

    // User settings
    @Published var ambientCelsius: Double {
        didSet { persistSettings() }
    }
    @Published var heatFraction: Double {
        didSet { persistSettings() }
    }
    @Published var basalHeatFraction: Double {
        didSet { persistSettings() }
    }

    // Outputs
    @Published private(set) var entropyTodayKJPerK: Double?
    @Published private(set) var activeEnergyKcal: Double?
    @Published private(set) var basalEnergyKcal: Double?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var weatherStatus = "Manual ambient"
    @Published private(set) var healthStatus: String?

    init(
        health: HealthProviding = makeDefaultHealthProvider(),
        weather: WeatherProviding = makeDefaultWeatherProvider(),
        ambientCelsius: Double? = nil,
        heatFraction: Double? = nil
    ) {
        self.health = health
        self.weather = weather

        let defaults = UserDefaults.standard
        self.ambientCelsius = ambientCelsius ?? defaults.double(forKey: Keys.ambientC)
        if defaults.object(forKey: Keys.ambientC) == nil && ambientCelsius == nil {
            self.ambientCelsius = 22 // default comfortable room temp
        }
        self.heatFraction = heatFraction ?? defaults.double(forKey: Keys.heatFraction)
        if defaults.object(forKey: Keys.heatFraction) == nil && heatFraction == nil {
            self.heatFraction = 0.85 // assume ~85% of metabolic energy as heat now
        }
        self.basalHeatFraction = defaults.object(forKey: Keys.basalHeatFraction) as? Double ?? 1.0
    }

    private struct Keys {
        static let ambientC = "ambient.celsius"
        static let heatFraction = "heat.fraction"
        static let basalHeatFraction = "heat.fraction.basal"
    }

    private func persistSettings() {
        let d = UserDefaults.standard
        d.set(ambientCelsius, forKey: Keys.ambientC)
        d.set(heatFraction, forKey: Keys.heatFraction)
        d.set(basalHeatFraction, forKey: Keys.basalHeatFraction)
    }

    var entropyTodayFormatted: String {
        EntropyCalculator.formatEntropy(entropyTodayKJPerK ?? 0)
    }

    var activeEnergyFormatted: String { EntropyCalculator.formatEnergyKcal(activeEnergyKcal) }
    var basalEnergyFormatted: String { EntropyCalculator.formatEnergyKcal(basalEnergyKcal) }

    var ambientTemperatureFormatted: String {
        String(format: "%.0f °C", ambientCelsius)
    }

    var lastUpdatedFormatted: String {
        guard let lastUpdated else { return "Not updated" }
        return "Updated " + lastUpdated.formatted(date: .omitted, time: .shortened)
    }

    func ensureAuthorizedAndRefresh() async {
        do {
            let ok = try await health.requestAuthorization()
            guard ok else {
                healthStatus = "Health unavailable"
                await refreshAmbientTemperature()
                return
            }
            healthStatus = nil
            await refreshToday()
        } catch {
            healthStatus = "Health unavailable"
            print("Health authorization error: \(error)")
            await refreshAmbientTemperature()
        }
    }

    func runLiveRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await refreshToday()
        }
    }

    func refreshToday(now: Date = Date(), updateWeather: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if updateWeather {
            await refreshAmbientTemperature()
        }

        let startOfDay = Calendar.current.startOfDay(for: now)
        do {
            async let active = health.activeEnergyKcal(from: startOfDay, to: now)
            async let basal = health.basalEnergyKcal(from: startOfDay, to: now)
            let (a, b) = try await (active, basal)
            self.activeEnergyKcal = a
            self.basalEnergyKcal = b
            self.healthStatus = nil
            self.entropyTodayKJPerK = EntropyCalculator.entropyKJPerK(activeKcal: a,
                                                                       basalKcal: b,
                                                                       ambientCelsius: ambientCelsius,
                                                                       activeHeatFraction: heatFraction,
                                                                       basalHeatFraction: basalHeatFraction)
            self.lastUpdated = now
        } catch {
            print("Health query error: \(error)")
            self.healthStatus = "Health unavailable"
            self.activeEnergyKcal = nil
            self.basalEnergyKcal = nil
            self.entropyTodayKJPerK = nil
        }
    }

    func refreshAmbientTemperature() async {
        do {
            ambientCelsius = try await weather.ambientCelsius()
            weatherStatus = "Live weather"
        } catch {
            weatherStatus = "Manual ambient"
            print("Weather update error: \(error)")
        }
    }
}
