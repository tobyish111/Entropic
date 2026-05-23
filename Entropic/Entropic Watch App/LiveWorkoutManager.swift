import Foundation
import HealthKit

@MainActor
final class LiveWorkoutManager: NSObject, ObservableObject {
    @Published private(set) var activeEnergyKcal: Double = 0
    @Published private(set) var basalEnergyKcal: Double = 0
    @Published private(set) var heartRateBPM: Double?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var status = "Ready"

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var elapsedTask: Task<Void, Never>?

    var hasActiveWorkout: Bool {
        isRunning || isPaused
    }

    var activeEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(activeEnergyKcal)
    }

    var basalEnergyFormatted: String {
        EntropyCalculator.formatEnergyKcal(basalEnergyKcal)
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

    func startWorkout() async {
        guard !hasActiveWorkout else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Health unavailable"
            return
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil,
              Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil else {
            status = "Add Health permissions"
            print("Live workout skipped: add NSHealthShareUsageDescription and NSHealthUpdateUsageDescription to the watch app target Info.plist settings.")
            return
        }

        do {
            try await requestWorkoutAuthorization()
            try configureAndStartSession()
        } catch {
            status = "Workout unavailable"
            print("Live workout start error: \(error)")
        }
    }

    func pauseWorkout() {
        guard isRunning else { return }
        session?.pause()
    }

    func resumeWorkout() {
        guard isPaused else { return }
        session?.resume()
    }

    func endWorkout() {
        guard hasActiveWorkout else { return }
        let endDate = Date()
        status = "Ending"
        session?.end()
        elapsedTask?.cancel()
        elapsedTask = nil

        let workoutBuilder = builder
        workoutBuilder?.endCollection(withEnd: endDate) { [weak self] success, error in
            guard success, error == nil else {
                Task { @MainActor [weak self] in
                    self?.resetAfterEnd(status: "Ended")
                }
                return
            }

            workoutBuilder?.finishWorkout { _, finishError in
                Task { @MainActor [weak self] in
                    if let finishError {
                        print("Live workout finish error: \(finishError)")
                    }
                    self?.resetAfterEnd(status: "Ended")
                }
            }
        }
    }

    func entropyKJPerK(ambientCelsius: Double, activeHeatFraction: Double, basalHeatFraction: Double) -> Double {
        EntropyCalculator.entropyKJPerK(activeKcal: activeEnergyKcal,
                                        basalKcal: basalEnergyKcal,
                                        ambientCelsius: ambientCelsius,
                                        activeHeatFraction: activeHeatFraction,
                                        basalHeatFraction: basalHeatFraction)
    }

    private func requestWorkoutAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!
        ]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: WorkoutError.authorizationDenied)
                }
            }
        }
    }

    private func configureAndStartSession() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown

        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder
        self.startDate = Date()
        self.activeEnergyKcal = 0
        self.basalEnergyKcal = 0
        self.heartRateBPM = nil
        self.elapsedSeconds = 0
        self.status = "Starting"

        guard let startDate else { return }
        session.startActivity(with: startDate)
        builder.beginCollection(withStart: startDate) { [weak self] success, error in
            Task { @MainActor in
                guard success, error == nil else {
                    self?.status = "Workout unavailable"
                    if let error {
                        print("Live workout collection error: \(error)")
                    }
                    return
                }
                self?.status = "Live"
            }
        }
        startElapsedTimer()
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateElapsedTime()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateElapsedTime() {
        guard let startDate else { return }
        elapsedSeconds = Date().timeIntervalSince(startDate)
    }

    private func updateStatistics(for types: Set<HKSampleType>) {
        guard let builder else { return }

        if let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned), types.contains(activeType) {
            activeEnergyKcal = builder.statistics(for: activeType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeEnergyKcal
        }

        if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned), types.contains(basalType) {
            basalEnergyKcal = builder.statistics(for: basalType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? basalEnergyKcal
        }

        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate), types.contains(heartRateType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRateBPM = builder.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(for: unit) ?? heartRateBPM
        }

        updateElapsedTime()
    }

    private func resetAfterEnd(status: String) {
        self.status = status
        self.isRunning = false
        self.isPaused = false
        self.session = nil
        self.builder = nil
        self.startDate = nil
    }

    private enum WorkoutError: Error {
        case authorizationDenied
    }
}

extension LiveWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                isRunning = true
                isPaused = false
                status = "Live"
            case .paused:
                isRunning = false
                isPaused = true
                status = "Paused"
            case .ended:
                isRunning = false
                isPaused = false
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            status = "Workout failed"
            isRunning = false
            isPaused = false
            elapsedTask?.cancel()
            print("Live workout session error: \(error)")
        }
    }
}

extension LiveWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            updateStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
