import Foundation

/// Computes human heat/entropy export based on energy expenditure and ambient temperature.
public struct EntropyCalculator {
    /// Converts kilocalories to kilojoules.
    public static let kJPerKcal: Double = 4.184

    /// Minimum Kelvin to avoid division by zero or negative temperatures.
    public static let minKelvin: Double = 1.0

    /// Compute entropy exported to the environment in kJ/K.
    /// - Parameters:
    ///   - energyKcal: Energy expended (kcal) to consider as heat output.
    ///   - ambientCelsius: Ambient temperature in °C.
    ///   - heatFraction: Fraction [0,1] of energy that is effectively exported as heat to the environment now.
    /// - Returns: Entropy in kJ/K.
    public static func entropyKJPerK(energyKcal: Double,
                                     ambientCelsius: Double,
                                     heatFraction: Double) -> Double {
        return entropyKJPerK(activeKcal: energyKcal,
                             basalKcal: 0,
                             ambientCelsius: ambientCelsius,
                             activeHeatFraction: heatFraction,
                             basalHeatFraction: heatFraction)
    }

    /// Compute entropy exported to the environment in kJ/K using separate active/basal contributions.
    /// - Parameters:
    ///   - activeKcal: Active energy expenditure (kcal).
    ///   - basalKcal: Basal energy expenditure (kcal).
    ///   - ambientCelsius: Ambient temperature in °C.
    ///   - activeHeatFraction: Fraction [0,1] of active energy exported as heat now.
    ///   - basalHeatFraction: Fraction [0,1] of basal energy exported as heat now (typically ~1.0).
    /// - Returns: Entropy in kJ/K.
    public static func entropyKJPerK(activeKcal: Double,
                                     basalKcal: Double,
                                     ambientCelsius: Double,
                                     activeHeatFraction: Double,
                                     basalHeatFraction: Double) -> Double {
        let T = max(celsiusToKelvin(ambientCelsius), minKelvin)
        let activeHeatKJ = max(activeKcal, 0) * kJPerKcal * clamp01(activeHeatFraction)
        let basalHeatKJ = max(basalKcal, 0) * kJPerKcal * clamp01(basalHeatFraction)
        let heatKJ = activeHeatKJ + basalHeatKJ
        return heatKJ / T
    }

    /// Clamp a value to [0,1].
    public static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    /// Celsius to Kelvin conversion.
    public static func celsiusToKelvin(_ c: Double) -> Double { c + 273.15 }

    /// Kelvin to Celsius conversion.
    public static func kelvinToCelsius(_ k: Double) -> Double { k - 273.15 }
}

extension EntropyCalculator {
    /// Human-readable formatting helpers.
    public static func formatEntropy(_ s: Double) -> String {
        if s.isNaN || s.isInfinite { return "— kJ/K" }
        // show with one decimal up to 999.9, otherwise no decimals
        let absS = abs(s)
        let formatted: String
        if absS < 1000 { formatted = String(format: "%.1f", s) } else { formatted = String(format: "%.0f", s) }
        return "\(formatted) kJ/K"
    }

    public static func formatEnergyKcal(_ e: Double?) -> String {
        guard let e else { return "— kcal" }
        if e.isNaN || e.isInfinite { return "— kcal" }
        return String(format: "%.0f kcal", e)
    }
}
