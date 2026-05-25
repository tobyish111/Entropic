import Foundation
import SwiftUI

@MainActor
final class EntropicDashboardViewModel: ObservableObject {
    @Published private(set) var entropyTodayKJPerK: Double?
    @Published private(set) var activeEnergyKcal: Double?
    @Published private(set) var basalEnergyKcal: Double?
    @Published private(set) var hourlyPoints: [EntropyTrendPoint] = []
    @Published private(set) var dailyPoints: [EntropyTrendPoint] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var status = "Ready"
    @Published private(set) var isRefreshing = false

    private let health: EntropicHealthProviding
    private let ambientCelsius: Double
    private let activeHeatFraction: Double
    private let basalHeatFraction: Double

    init(
        health: EntropicHealthProviding = makeDefaultEntropicHealthProvider(),
        ambientCelsius: Double = 22,
        activeHeatFraction: Double = 0.85,
        basalHeatFraction: Double = 1.0
    ) {
        self.health = health
        self.ambientCelsius = ambientCelsius
        self.activeHeatFraction = activeHeatFraction
        self.basalHeatFraction = basalHeatFraction
    }

    var entropyTodayFormatted: String {
        EntropyCalculator.formatEntropy(entropyTodayKJPerK)
    }

    var activeEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(activeEnergyKcal)
    }

    var basalEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(basalEnergyKcal)
    }

    var ambientFormatted: String {
        String(format: "%.0f °C", ambientCelsius)
    }

    var lastUpdatedFormatted: String {
        guard let lastUpdated else { return "Not updated" }
        return lastUpdated.formatted(date: .omitted, time: .shortened)
    }

    var fourteenDayAverageFormatted: String {
        let values = dailyPoints.map(\.entropyKJPerK).filter { $0.isFinite }
        guard !values.isEmpty else { return "-- kJ/K" }
        return EntropyCalculator.formatEntropy(values.reduce(0, +) / Double(values.count))
    }

    var trendDirection: String {
        guard dailyPoints.count >= 2,
              let first = dailyPoints.first?.entropyKJPerK,
              let last = dailyPoints.last?.entropyKJPerK else {
            return "Building trend"
        }

        let difference = last - first
        if abs(difference) < 0.1 { return "Stable" }
        return difference > 0 ? "Rising" : "Falling"
    }

    var peakHourFormatted: String {
        guard let point = hourlyPoints.max(by: { $0.entropyKJPerK < $1.entropyKJPerK }) else {
            return "--"
        }
        return point.date.formatted(date: .omitted, time: .shortened)
    }

    var heatReleasedFormatted: String {
        guard let heatReleasedKJ else { return "-- kJ" }
        return String(format: "%.0f kJ", heatReleasedKJ)
    }

    var entropyRateFormatted: String {
        guard let entropyRateKJPerKPerHour else { return "-- kJ/K/hr" }
        return String(format: "%.2f kJ/K/hr", entropyRateKJPerKPerHour)
    }

    var activeEntropyShareFormatted: String {
        formatPercent(activeEntropyShare)
    }

    var basalEntropyShareFormatted: String {
        formatPercent(basalEntropyShare)
    }

    var trendDeltaFormatted: String {
        guard dailyPoints.count >= 2,
              let first = dailyPoints.first?.entropyKJPerK,
              let last = dailyPoints.last?.entropyKJPerK else {
            return "-- kJ/K"
        }

        let delta = last - first
        return String(format: "%@%.1f kJ/K", delta >= 0 ? "+" : "", delta)
    }

    var peakDayFormatted: String {
        guard let point = dailyPoints.max(by: { $0.entropyKJPerK < $1.entropyKJPerK }) else {
            return "--"
        }
        return point.date.formatted(date: .abbreviated, time: .omitted)
    }

    var peakDayEntropyFormatted: String {
        guard let point = dailyPoints.max(by: { $0.entropyKJPerK < $1.entropyKJPerK }) else {
            return "-- kJ/K"
        }
        return EntropyCalculator.formatEntropy(point.entropyKJPerK)
    }

    var entropyLevel: String {
        guard let entropyTodayKJPerK else { return "Waiting for data" }
        switch entropyTodayKJPerK {
        case ..<5:
            return "Light"
        case ..<15:
            return "Moderate"
        case ..<30:
            return "High"
        default:
            return "Very high"
        }
    }

    var analysisSummary: String {
        guard let entropyTodayKJPerK, let heatReleasedKJ else {
            return "Once Health data is available, Entropic will translate today's active and basal energy into heat released and entropy produced."
        }

        return String(format: "Today is a %@ entropy day: about %.0f kJ of metabolic heat has dispersed into the environment, producing %.1f kJ/K of entropy at the current ambient estimate.", entropyLevel.lowercased(), heatReleasedKJ, entropyTodayKJPerK)
    }

    var thermodynamicInterpretation: String {
        guard entropyTodayKJPerK != nil else {
            return "The model treats metabolism as chemical free energy becoming thermal motion. It estimates thermodynamic entropy, not information entropy or a direct quantum measurement."
        }

        return "In microscopic terms, the heat you release opens more accessible environmental microstates. The effect is tiny relative to planetary entropy, but directionally real: ordered chemical energy becomes less recoverable thermal energy spread across air, skin, clothing, and radiation."
    }

    var recoveryReadout: String {
        guard let activeEntropyShare else {
            return "Active and basal shares will appear after the next refresh."
        }

        if activeEntropyShare > 0.35 {
            return "Activity is a large part of today's entropy production, so the trend is being driven by workout load more than background metabolism."
        }

        return "Basal metabolism is dominating today's entropy production, so the curve mostly reflects time awake, body maintenance, and ambient conditions."
    }

    private var heatReleasedKJ: Double? {
        guard let activeHeatKJ, let basalHeatKJ else { return nil }
        return activeHeatKJ + basalHeatKJ
    }

    private var activeHeatKJ: Double? {
        guard let activeEnergyKcal else { return nil }
        return activeEnergyKcal * 4.184 * activeHeatFraction
    }

    private var basalHeatKJ: Double? {
        guard let basalEnergyKcal else { return nil }
        return basalEnergyKcal * 4.184 * basalHeatFraction
    }

    private var activeEntropyShare: Double? {
        guard let activeHeatKJ, let heatReleasedKJ, heatReleasedKJ > 0 else { return nil }
        return activeHeatKJ / heatReleasedKJ
    }

    private var basalEntropyShare: Double? {
        guard let basalHeatKJ, let heatReleasedKJ, heatReleasedKJ > 0 else { return nil }
        return basalHeatKJ / heatReleasedKJ
    }

    private var entropyRateKJPerKPerHour: Double? {
        guard let entropyTodayKJPerK else { return nil }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let hoursElapsed = max(now.timeIntervalSince(startOfDay) / 3600, 0.25)
        return entropyTodayKJPerK / hoursElapsed
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--%" }
        return String(format: "%.0f%%", value * 100)
    }

    func start() async {
        do {
            status = "Requesting Health access"
            let authorized = try await health.requestAuthorization()
            guard authorized else {
                status = "Health unavailable"
                return
            }

            status = "Live"
            await refresh()
        } catch {
            status = "Health unavailable"
            print("iOS Health authorization error: \(error)")
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        do {
            async let todayTotals = health.energyTotals(from: startOfDay, to: now)
            async let hourly = health.hourlyEnergyTotals(hours: 12, endingAt: now)
            async let daily = health.dailyEnergyTotals(days: 14, endingAt: now)

            let (totals, hourlyPoints, dailyPoints) = try await (todayTotals, hourly, daily)
            self.activeEnergyKcal = totals.activeKcal
            self.basalEnergyKcal = totals.basalKcal
            self.entropyTodayKJPerK = EntropyCalculator.entropyKJPerK(activeKcal: totals.activeKcal,
                                                                       basalKcal: totals.basalKcal,
                                                                       ambientCelsius: ambientCelsius,
                                                                       activeHeatFraction: activeHeatFraction,
                                                                       basalHeatFraction: basalHeatFraction)
            self.hourlyPoints = hourlyPoints
            self.dailyPoints = dailyPoints
            self.lastUpdated = now
            self.status = "Live"
        } catch {
            status = "Refresh failed"
            print("iOS entropy refresh error: \(error)")
        }
    }

    func runRealtimeLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}
