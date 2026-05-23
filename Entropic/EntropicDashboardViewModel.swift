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
