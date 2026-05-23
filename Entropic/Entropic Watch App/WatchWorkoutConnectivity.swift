import Foundation
import WatchConnectivity

@MainActor
final class WatchWorkoutConnectivity: NSObject, ObservableObject {
    static let shared = WatchWorkoutConnectivity()

    @Published private(set) var status = "Phone link ready"

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
    }

    func sendWorkoutUpdate(entropyKJPerK: Double,
                           activeKcal: Double,
                           basalKcal: Double,
                           heartRateBPM: Double?,
                           elapsedSeconds: TimeInterval,
                           ambientCelsius: Double,
                           state: String) {
        guard let session, session.activationState == .activated else {
            status = "Phone link inactive"
            return
        }

        var payload: [String: Any] = [
            "kind": "liveWorkoutEntropy",
            "entropyKJPerK": entropyKJPerK,
            "activeKcal": activeKcal,
            "basalKcal": basalKcal,
            "elapsedSeconds": elapsedSeconds,
            "ambientCelsius": ambientCelsius,
            "state": state,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let heartRateBPM {
            payload["heartRateBPM"] = heartRateBPM
        }

        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("WatchConnectivity context update error: \(error)")
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("WatchConnectivity live message error: \(error)")
            }
            status = "Phone linked"
        } else {
            _ = session.transferUserInfo(payload)
            status = "Queued for phone"
        }
    }
}

extension WatchWorkoutConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error {
                status = "Phone link failed"
                print("WatchConnectivity activation error: \(error)")
            } else {
                status = activationState == .activated ? "Phone link ready" : "Phone link inactive"
            }
        }
    }
}
