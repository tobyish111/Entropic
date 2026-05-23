import Foundation

struct EntropyCalculator {
    static let kJPerKcal: Double = 4.184
    static let minKelvin: Double = 1.0

    static func entropyKJPerK(activeKcal: Double,
                              basalKcal: Double,
                              ambientCelsius: Double,
                              activeHeatFraction: Double,
                              basalHeatFraction: Double) -> Double {
        let temperatureKelvin = max(ambientCelsius + 273.15, minKelvin)
        let activeHeatKJ = max(activeKcal, 0) * kJPerKcal * clamp01(activeHeatFraction)
        let basalHeatKJ = max(basalKcal, 0) * kJPerKcal * clamp01(basalHeatFraction)
        return (activeHeatKJ + basalHeatKJ) / temperatureKelvin
    }

    static func formatEntropy(_ entropy: Double?) -> String {
        guard let entropy, entropy.isFinite else { return "-- kJ/K" }
        let formatted: String
        if abs(entropy) < 1000 {
            formatted = String(format: "%.1f", entropy)
        } else {
            formatted = String(format: "%.0f", entropy)
        }
        return "\(formatted) kJ/K"
    }

    static func formatEnergyKcal(_ energy: Double?) -> String {
        guard let energy, energy.isFinite else { return "-- kcal" }
        return String(format: "%.0f kcal", energy)
    }

    static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
