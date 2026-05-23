import Foundation

#if DEBUG
private enum SampleEntropyData {
    static let ambientCelsius = 21.5

    static func activeKcal(hour: Int) -> Double {
        let warmup = gaussian(x: Double(hour), center: 7.0, width: 1.2, height: 120)
        let commute = gaussian(x: Double(hour), center: 12.0, width: 1.0, height: 75)
        let workout = gaussian(x: Double(hour), center: 18.0, width: 1.5, height: 230)
        return max(0, 10 + warmup + commute + workout)
    }

    static func basalKcal(hours: Double) -> Double {
        max(0, hours) * 72
    }

    static func gaussian(x: Double, center: Double, width: Double, height: Double) -> Double {
        height * exp(-pow(x - center, 2) / (2 * pow(width, 2)))
    }
}

final class SampleHealthProvider: HealthProviding {
    func requestAuthorization() async throws -> Bool {
        true
    }

    func activeEnergyKcal(from start: Date, to end: Date) async throws -> Double {
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

    func basalEnergyKcal(from start: Date, to end: Date) async throws -> Double {
        SampleEntropyData.basalKcal(hours: end.timeIntervalSince(start) / 3600)
    }
}

final class SampleWeatherProvider: WeatherProviding {
    func ambientCelsius() async throws -> Double {
        SampleEntropyData.ambientCelsius
    }
}

func makeDefaultHealthProvider() -> HealthProviding {
    #if targetEnvironment(simulator)
    return SampleHealthProvider()
    #else
    return HealthKitManager()
    #endif
}

func makeDefaultWeatherProvider() -> WeatherProviding {
    #if targetEnvironment(simulator)
    return SampleWeatherProvider()
    #else
    return DefaultWeatherProvider()
    #endif
}
#else
func makeDefaultHealthProvider() -> HealthProviding {
    HealthKitManager()
}

func makeDefaultWeatherProvider() -> WeatherProviding {
    DefaultWeatherProvider()
}
#endif
