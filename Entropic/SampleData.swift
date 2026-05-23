import Foundation

#if DEBUG
private enum SampleEntropyData {
    static let ambientCelsius = 21.5
    static let activeHeatFraction = 0.85
    static let basalHeatFraction = 1.0

    static func activeKcal(hour: Int) -> Double {
        let morningWorkout = gaussian(x: Double(hour), center: 7.5, width: 1.4, height: 210)
        let lunchWalk = gaussian(x: Double(hour), center: 12.5, width: 1.1, height: 95)
        let eveningWorkout = gaussian(x: Double(hour), center: 18.0, width: 1.6, height: 260)
        let baseline = 8 + 5 * sin(Double(hour) / 24.0 * .pi * 2)
        return max(0, baseline + morningWorkout + lunchWalk + eveningWorkout)
    }

    static func basalKcal(hours: Double) -> Double {
        max(0, hours) * 72
    }

    static func dailyActiveKcal(dayOffset: Int) -> Double {
        let weeklyPattern = [520.0, 610.0, 580.0, 740.0, 690.0, 880.0, 430.0]
        let pattern = weeklyPattern[abs(dayOffset) % weeklyPattern.count]
        let drift = Double(dayOffset) * 9
        return max(160, pattern + drift)
    }

    static func gaussian(x: Double, center: Double, width: Double, height: Double) -> Double {
        height * exp(-pow(x - center, 2) / (2 * pow(width, 2)))
    }

    static func entropy(activeKcal: Double, basalKcal: Double) -> Double {
        EntropyCalculator.entropyKJPerK(activeKcal: activeKcal,
                                        basalKcal: basalKcal,
                                        ambientCelsius: ambientCelsius,
                                        activeHeatFraction: activeHeatFraction,
                                        basalHeatFraction: basalHeatFraction)
    }
}

final class SampleEntropicHealthProvider: EntropicHealthProviding {
    func requestAuthorization() async throws -> Bool {
        true
    }

    func energyTotals(from start: Date, to end: Date) async throws -> EnergyTotals {
        let hours = max(0, end.timeIntervalSince(start) / 3600)
        let active = sampleActiveKcal(from: start, to: end)
        let basal = SampleEntropyData.basalKcal(hours: hours)
        return EnergyTotals(activeKcal: active, basalKcal: basal)
    }

    func dailyEnergyTotals(days: Int, endingAt endDate: Date) async throws -> [EntropyTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: endDate)

        return (0..<days).compactMap { index in
            let offset = index - (days - 1)
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let active = SampleEntropyData.dailyActiveKcal(dayOffset: offset)
            let basal = SampleEntropyData.basalKcal(hours: offset == 0 ? currentHourFraction(endDate) : 24)
            return EntropyTrendPoint(date: date,
                                     activeKcal: active,
                                     basalKcal: basal,
                                     entropyKJPerK: SampleEntropyData.entropy(activeKcal: active, basalKcal: basal))
        }
    }

    func hourlyEnergyTotals(hours: Int, endingAt endDate: Date) async throws -> [EntropyTrendPoint] {
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: endDate)?.start ?? endDate

        return (0..<hours).compactMap { index in
            let offset = index - (hours - 1)
            guard let date = calendar.date(byAdding: .hour, value: offset, to: currentHour) else { return nil }
            let hour = calendar.component(.hour, from: date)
            let active = SampleEntropyData.activeKcal(hour: hour)
            let basal = SampleEntropyData.basalKcal(hours: 1)
            return EntropyTrendPoint(date: date,
                                     activeKcal: active,
                                     basalKcal: basal,
                                     entropyKJPerK: SampleEntropyData.entropy(activeKcal: active, basalKcal: basal))
        }
    }

    private func sampleActiveKcal(from start: Date, to end: Date) -> Double {
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: start)
        let endHour = calendar.component(.hour, from: end)
        let endMinute = calendar.component(.minute, from: end)
        let wrappedEndHour = endHour < startHour ? endHour + 24 : endHour

        return (startHour...wrappedEndHour).reduce(0) { total, rawHour in
            let hour = rawHour % 24
            let fraction = rawHour == wrappedEndHour ? max(0.05, Double(endMinute) / 60.0) : 1.0
            return total + SampleEntropyData.activeKcal(hour: hour) * fraction
        }
    }

    private func currentHourFraction(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0
    }
}

func makeDefaultEntropicHealthProvider() -> EntropicHealthProviding {
    #if targetEnvironment(simulator)
    return SampleEntropicHealthProvider()
    #else
    return EntropicHealthStore()
    #endif
}

extension LiveWatchWorkoutSnapshot {
    static func sample(now: Date = Date()) -> LiveWatchWorkoutSnapshot {
        LiveWatchWorkoutSnapshot(entropyKJPerK: SampleEntropyData.entropy(activeKcal: 92, basalKcal: 38),
                                 activeKcal: 92,
                                 basalKcal: 38,
                                 heartRateBPM: 143,
                                 elapsedSeconds: 11 * 60 + 24,
                                 ambientCelsius: SampleEntropyData.ambientCelsius,
                                 state: "Live",
                                 timestamp: now)
    }
}
#else
func makeDefaultEntropicHealthProvider() -> EntropicHealthProviding {
    EntropicHealthStore()
}
#endif
