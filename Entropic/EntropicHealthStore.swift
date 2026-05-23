import Foundation
import HealthKit

struct EnergyTotals {
    var activeKcal: Double
    var basalKcal: Double

    static let zero = EnergyTotals(activeKcal: 0, basalKcal: 0)
}

struct EntropyTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let activeKcal: Double
    let basalKcal: Double
    let entropyKJPerK: Double
}

protocol EntropicHealthProviding: AnyObject {
    func requestAuthorization() async throws -> Bool
    func energyTotals(from start: Date, to end: Date) async throws -> EnergyTotals
    func dailyEnergyTotals(days: Int, endingAt endDate: Date) async throws -> [EntropyTrendPoint]
    func hourlyEnergyTotals(hours: Int, endingAt endDate: Date) async throws -> [EntropyTrendPoint]
}

final class EntropicHealthStore: EntropicHealthProviding {
    private let store = HKHealthStore()
    private let ambientCelsius: Double
    private let activeHeatFraction: Double
    private let basalHeatFraction: Double

    init(ambientCelsius: Double = 22, activeHeatFraction: Double = 0.85, basalHeatFraction: Double = 1.0) {
        self.ambientCelsius = ambientCelsius
        self.activeHeatFraction = activeHeatFraction
        self.basalHeatFraction = basalHeatFraction
    }

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil else {
            print("HealthKit authorization skipped: add NSHealthShareUsageDescription to the iOS app target Info.plist settings.")
            return false
        }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
        ]

        return try await withCheckedThrowingContinuation { continuation in
            store.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func energyTotals(from start: Date, to end: Date) async throws -> EnergyTotals {
        async let active = sumQuantity(.activeEnergyBurned, from: start, to: end)
        async let basal = sumQuantity(.basalEnergyBurned, from: start, to: end)
        return try await EnergyTotals(activeKcal: active, basalKcal: basal)
    }

    func dailyEnergyTotals(days: Int, endingAt endDate: Date = Date()) async throws -> [EntropyTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: endDate)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        return try await points(from: startDay, count: days, component: .day)
    }

    func hourlyEnergyTotals(hours: Int, endingAt endDate: Date = Date()) async throws -> [EntropyTrendPoint] {
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: endDate)?.start ?? endDate
        let startHour = calendar.date(byAdding: .hour, value: -(hours - 1), to: currentHour) ?? currentHour

        return try await points(from: startHour, count: hours, component: .hour)
    }

    private func points(from startDate: Date, count: Int, component: Calendar.Component) async throws -> [EntropyTrendPoint] {
        let calendar = Calendar.current
        var points: [EntropyTrendPoint] = []
        points.reserveCapacity(count)

        for offset in 0..<count {
            guard let start = calendar.date(byAdding: component, value: offset, to: startDate),
                  let end = calendar.date(byAdding: component, value: 1, to: start) else {
                continue
            }

            let totals = try await energyTotals(from: start, to: min(end, Date()))
            let entropy = EntropyCalculator.entropyKJPerK(activeKcal: totals.activeKcal,
                                                          basalKcal: totals.basalKcal,
                                                          ambientCelsius: ambientCelsius,
                                                          activeHeatFraction: activeHeatFraction,
                                                          basalHeatFraction: basalHeatFraction)
            points.append(EntropyTrendPoint(date: start,
                                            activeKcal: totals.activeKcal,
                                            basalKcal: totals.basalKcal,
                                            entropyKJPerK: entropy))
        }

        return points
    }

    private func sumQuantity(_ identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
