import Foundation
import HealthKit

public protocol HealthProviding: AnyObject {
    func requestAuthorization() async throws -> Bool
    func activeEnergyKcal(from start: Date, to end: Date) async throws -> Double
    func basalEnergyKcal(from start: Date, to end: Date) async throws -> Double
}

public final class HealthKitManager: HealthProviding {
    private let store = HKHealthStore()

    public init() {}

    public func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil else {
            print("HealthKit authorization skipped: add NSHealthShareUsageDescription to the watch app target Info.plist settings.")
            return false
        }

        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
        ]
        return try await withCheckedThrowingContinuation { cont in
            store.requestAuthorization(toShare: nil, read: types) { success, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: success) }
            }
        }
    }

    public func activeEnergyKcal(from start: Date, to end: Date) async throws -> Double {
        try await sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
    }

    public func basalEnergyKcal(from start: Date, to end: Date) async throws -> Double {
        try await sumQuantity(.basalEnergyBurned, unit: .kilocalorie(), from: start, to: end)
    }

    private func sumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        return try await withCheckedThrowingContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { cont.resume(throwing: error) }
                else if let sum = stats?.sumQuantity() {
                    cont.resume(returning: sum.doubleValue(for: unit))
                } else {
                    cont.resume(returning: 0)
                }
            }
            self.store.execute(query)
        }
    }
}
