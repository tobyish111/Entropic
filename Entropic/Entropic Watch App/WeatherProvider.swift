import Foundation

public protocol WeatherProviding: AnyObject {
    func ambientCelsius() async throws -> Double
}

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(WeatherKit)
import WeatherKit
#endif

public enum WeatherError: Error {
    case unavailable
    case locationDenied
}

public final class DefaultWeatherProvider: WeatherProviding {
    private let locationProvider: LocationProviding?

    public init(locationProvider: LocationProviding? = DefaultLocationProvider()) {
        self.locationProvider = locationProvider
    }

    public func ambientCelsius() async throws -> Double {
        #if canImport(WeatherKit)
        guard let locationProvider else { throw WeatherError.unavailable }
        let loc = try await locationProvider.requestLocation()
        if #available(iOS 16.0, watchOS 9.0, *) {
            let service = WeatherService.shared
            let weather = try await service.weather(for: loc)
            let celsius = weather.currentWeather.temperature.converted(to: .celsius).value
            return celsius
        } else {
            throw WeatherError.unavailable
        }
        #else
        throw WeatherError.unavailable
        #endif
    }
}

public protocol LocationProviding: AnyObject {
    func requestLocation() async throws -> CLLocation
}

public final class DefaultLocationProvider: NSObject, LocationProviding {
    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Error>?

    public override init() {
        super.init()
        manager.delegate = self
    }

    public func requestLocation() async throws -> CLLocation {
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
            print("Weather update skipped: add NSLocationWhenInUseUsageDescription to the watch app target Info.plist settings.")
            throw WeatherError.unavailable
        }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.authContinuation = cont
                self.manager.requestWhenInUseAuthorization()
            }
        } else if status == .denied || status == .restricted {
            throw WeatherError.locationDenied
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = cont
            self.manager.requestLocation()
        }
    }
    #else
    public func requestLocation() async throws -> CLLocation { throw WeatherError.unavailable }
    #endif
}

#if canImport(CoreLocation)
extension DefaultLocationProvider: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            locationContinuation?.resume(returning: loc)
            locationContinuation = nil
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authContinuation?.resume()
            authContinuation = nil
        case .denied, .restricted:
            authContinuation?.resume(throwing: WeatherError.locationDenied)
            authContinuation = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
#endif
