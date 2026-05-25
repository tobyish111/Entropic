import Foundation

@MainActor
final class AppleWorkoutFollower: ObservableObject {
    @Published private(set) var activeEnergyKcal: Double = 0
    @Published private(set) var basalEnergyKcal: Double = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isFollowing = false
    @Published private(set) var status = "Apple Idle"

    private let health: HealthProviding
    private var baselineActiveKcal: Double?
    private var baselineBasalKcal: Double?
    private var lastObservedActiveKcal: Double?
    private var startedAt: Date?
    private var lastIncreaseAt: Date?

    init(health: HealthProviding = makeDefaultHealthProvider()) {
        self.health = health
    }

    var activeEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(activeEnergyKcal)
    }

    var basalEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(basalEnergyKcal)
    }

    var elapsedFormatted: String {
        let totalSeconds = Int(elapsedSeconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func entropyKJPerK(ambientCelsius: Double, activeHeatFraction: Double, basalHeatFraction: Double) -> Double {
        EntropyCalculator.entropyKJPerK(activeKcal: activeEnergyKcal,
                                        basalKcal: basalEnergyKcal,
                                        ambientCelsius: ambientCelsius,
                                        activeHeatFraction: activeHeatFraction,
                                        basalHeatFraction: basalHeatFraction)
    }

    func runMonitoringLoop() async {
        do {
            guard try await health.requestAuthorization() else {
                status = "Apple Off"
                return
            }
            status = "Apple Watch"
            try await poll(now: Date())
        } catch {
            status = "Apple Off"
            print("Apple workout follower authorization error: \(error)")
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await poll(now: Date())
            } catch {
                status = "Apple Off"
                print("Apple workout follower polling error: \(error)")
            }
        }
    }

    private func poll(now: Date) async throws {
        let startOfDay = Calendar.current.startOfDay(for: now)
        async let active = health.activeEnergyKcal(from: startOfDay, to: now)
        async let basal = health.basalEnergyKcal(from: startOfDay, to: now)
        let (totalActive, totalBasal) = try await (active, basal)

        defer {
            lastObservedActiveKcal = totalActive
        }

        guard let previousActive = lastObservedActiveKcal else {
            status = "Apple Watch"
            return
        }

        let activeDelta = totalActive - previousActive
        if activeDelta >= 0.5 {
            if !isFollowing {
                baselineActiveKcal = previousActive
                baselineBasalKcal = totalBasal
                startedAt = now
            }
            isFollowing = true
            status = "Apple Live"
            lastIncreaseAt = now
        }

        guard isFollowing else { return }

        activeEnergyKcal = max(0, totalActive - (baselineActiveKcal ?? totalActive))
        basalEnergyKcal = max(0, totalBasal - (baselineBasalKcal ?? totalBasal))
        if let startedAt {
            elapsedSeconds = now.timeIntervalSince(startedAt)
        }

        if let lastIncreaseAt, now.timeIntervalSince(lastIncreaseAt) > 90 {
            isFollowing = false
            status = "Apple Ended"
        }
    }
}
