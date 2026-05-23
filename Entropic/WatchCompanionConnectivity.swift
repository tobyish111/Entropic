import Foundation
import WatchConnectivity

struct LiveWatchWorkoutSnapshot: Identifiable, Equatable {
    let id = UUID()
    let entropyKJPerK: Double
    let activeKcal: Double
    let basalKcal: Double
    let heartRateBPM: Double?
    let elapsedSeconds: TimeInterval
    let ambientCelsius: Double
    let state: String
    let timestamp: Date

    var isRecent: Bool {
        Date().timeIntervalSince(timestamp) < 90 && state != "Ended"
    }

    var entropyFormatted: String {
        EntropyCalculator.formatEntropy(entropyKJPerK)
    }

    var activeEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(activeKcal)
    }

    var basalEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(basalKcal)
    }

    var heartRateFormatted: String {
        guard let heartRateBPM else { return "-- bpm" }
        return String(format: "%.0f bpm", heartRateBPM)
    }

    var elapsedFormatted: String {
        let totalSeconds = Int(elapsedSeconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var ambientFormatted: String {
        String(format: "%.0f °C", ambientCelsius)
    }
}

@MainActor
final class WatchCompanionConnectivity: NSObject, ObservableObject {
    static let shared = WatchCompanionConnectivity()

    @Published private(set) var snapshot: LiveWatchWorkoutSnapshot?
    @Published private(set) var status = "Watch link ready"

    private let session: WCSession?

    private override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()

        #if DEBUG && targetEnvironment(simulator)
        snapshot = .sample()
        status = "Sample watch"
        #endif
    }

    private func handle(payload: [String: Any]) {
        guard payload["kind"] as? String == "liveWorkoutEntropy",
              let entropyKJPerK = payload["entropyKJPerK"] as? Double,
              let activeKcal = payload["activeKcal"] as? Double,
              let basalKcal = payload["basalKcal"] as? Double,
              let elapsedSeconds = payload["elapsedSeconds"] as? Double,
              let ambientCelsius = payload["ambientCelsius"] as? Double,
              let state = payload["state"] as? String,
              let timestamp = payload["timestamp"] as? Double else {
            return
        }

        snapshot = LiveWatchWorkoutSnapshot(entropyKJPerK: entropyKJPerK,
                                            activeKcal: activeKcal,
                                            basalKcal: basalKcal,
                                            heartRateBPM: payload["heartRateBPM"] as? Double,
                                            elapsedSeconds: elapsedSeconds,
                                            ambientCelsius: ambientCelsius,
                                            state: state,
                                            timestamp: Date(timeIntervalSince1970: timestamp))
        status = state == "Ended" ? "Watch workout ended" : "Receiving watch workout"
    }
}

extension WatchCompanionConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error {
                status = "Watch link failed"
                print("WatchConnectivity activation error: \(error)")
            } else {
                status = activationState == .activated ? "Watch link ready" : "Watch link inactive"
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            status = "Watch link inactive"
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor in
            status = "Watch link reactivating"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            handle(payload: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handle(payload: message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handle(payload: userInfo)
        }
    }
}
