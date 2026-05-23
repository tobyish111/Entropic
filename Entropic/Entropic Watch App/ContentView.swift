import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EntropyViewModel()
    @StateObject private var workout = LiveWorkoutManager()
    @StateObject private var phoneLink = WatchWorkoutConnectivity.shared

    private var displayedEntropy: Double {
        if workout.hasActiveWorkout {
            return workout.entropyKJPerK(ambientCelsius: viewModel.ambientCelsius,
                                        activeHeatFraction: viewModel.heatFraction,
                                        basalHeatFraction: viewModel.basalHeatFraction)
        }
        return viewModel.entropyTodayKJPerK ?? 0
    }

    private var displayedEntropyFormatted: String {
        EntropyCalculator.formatEntropy(displayedEntropy)
    }

    var body: some View {
        NavigationStack {
            TabView {
                summaryPage
                workoutPage
                metricsPage
                meaningPage
                statusPage
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(ThermoBackground())
            .navigationTitle("Entropic")
            .toolbar {
                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                    Image(systemName: "thermometer.sun")
                }
            }
            .task {
                await viewModel.ensureAuthorizedAndRefresh()
            }
            .task {
                await viewModel.runLiveRefreshLoop()
            }
            .onChange(of: workout.elapsedSeconds) { _, _ in
                sendLiveWorkoutUpdate()
            }
            .onChange(of: workout.status) { _, _ in
                sendLiveWorkoutUpdate()
            }
        }
    }

    private var summaryPage: some View {
        pageScroll {
            VStack(spacing: 8) {
                Text(workout.hasActiveWorkout ? "LIVE" : "TODAY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(workout.hasActiveWorkout ? .green : .secondary)
                    .tracking(0.8)

                ThermoGaugeView(value: displayedEntropy,
                                target: 30,
                                unit: "kJ/K")
                .frame(height: 102)
                .accessibilityLabel(workout.hasActiveWorkout ? "Live workout entropy" : "Entropy today")
                .accessibilityValue(displayedEntropyFormatted)

                Text(displayedEntropyFormatted)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())

                metricRow(title: workout.hasActiveWorkout ? "Elapsed" : "Updated",
                          value: workout.hasActiveWorkout ? workout.elapsedFormatted : compactStatus(viewModel.lastUpdatedFormatted),
                          systemImage: workout.hasActiveWorkout ? "timer" : "arrow.clockwise",
                          tint: .green) {
                    if viewModel.isRefreshing && !workout.hasActiveWorkout {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var workoutPage: some View {
        pageScroll {
            VStack(spacing: 8) {
                pageHeader("Workout", systemImage: "figure.run", tint: workout.hasActiveWorkout ? .green : .orange)
                metricRow(title: "State", value: compactStatus(workout.status), systemImage: "record.circle", tint: workout.hasActiveWorkout ? .green : .orange)

                if workout.hasActiveWorkout {
                    HStack(spacing: 8) {
                        Button {
                            if workout.isPaused {
                                workout.resumeWorkout()
                            } else {
                                workout.pauseWorkout()
                            }
                        } label: {
                            Image(systemName: workout.isPaused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)

                        Button(role: .destructive) {
                            sendLiveWorkoutUpdate(stateOverride: "Ended")
                            workout.endWorkout()
                        } label: {
                            Image(systemName: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button {
                        Task {
                            await viewModel.refreshAmbientTemperature()
                            await workout.startWorkout()
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                metricRow(title: "Phone", value: compactStatus(phoneLink.status), systemImage: "iphone", tint: .blue)
            }
        }
    }

    private var metricsPage: some View {
        pageScroll {
            VStack(spacing: 6) {
                pageHeader("Metrics", systemImage: "waveform.path.ecg", tint: .orange)

                if workout.hasActiveWorkout {
                    metricRow(title: "Active", value: workout.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                    metricRow(title: "Basal", value: workout.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
                    metricRow(title: "Heart", value: workout.heartRateFormatted, systemImage: "heart.circle.fill", tint: .pink)
                    metricRow(title: "Ambient", value: viewModel.ambientTemperatureFormatted, systemImage: "cloud.sun.fill", tint: .cyan)
                } else {
                    metricRow(title: "Active", value: viewModel.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                    metricRow(title: "Basal", value: viewModel.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
                    metricRow(title: "Ambient", value: viewModel.ambientTemperatureFormatted, systemImage: "cloud.sun.fill", tint: .cyan)
                    metricRow(title: "Weather", value: compactStatus(viewModel.weatherStatus), systemImage: "location.fill", tint: .blue)
                }
            }
        }
    }

    private var meaningPage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 8) {
                pageHeader("Meaning", systemImage: "atom", tint: .orange)

                Text("Entropy is the arrow of time.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your heat makes the environment's microscopic quantum states less ordered and less reversible.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                metricRow(title: "Now", value: compactEntropyMeaning(for: displayedEntropy), systemImage: "thermometer.sun.fill", tint: .orange)
                metricRow(title: "Effect", value: "Universe +S", systemImage: "sparkles", tint: .purple)
                metricRow(title: "Caveat", value: "Estimate only", systemImage: "atom", tint: .blue)
            }
        }
    }

    private var statusPage: some View {
        pageScroll {
            VStack(spacing: 6) {
                pageHeader("Status", systemImage: "checkmark.seal.fill", tint: .green)
                metricRow(title: "Update", value: compactStatus(viewModel.lastUpdatedFormatted), systemImage: "arrow.clockwise", tint: .green) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                metricRow(title: "Weather", value: compactStatus(viewModel.weatherStatus), systemImage: "cloud.sun.fill", tint: .cyan)
                metricRow(title: "Phone", value: compactStatus(phoneLink.status), systemImage: "iphone", tint: .blue)

                if let healthStatus = viewModel.healthStatus {
                    metricRow(title: "Health", value: compactStatus(healthStatus), systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }
        }
    }

    private func pageScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 20)
        }
    }

    private func pageHeader(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func compactEntropyMeaning(for entropy: Double) -> String {
        switch entropy {
        case ..<5:
            "Light"
        case ..<15:
            "Moderate"
        case ..<30:
            "High"
        default:
            "Very high"
        }
    }

    private func sendLiveWorkoutUpdate(stateOverride: String? = nil) {
        guard workout.hasActiveWorkout || stateOverride == "Ended" else { return }

        phoneLink.sendWorkoutUpdate(entropyKJPerK: displayedEntropy,
                                    activeKcal: workout.activeEnergyKcal,
                                    basalKcal: workout.basalEnergyKcal,
                                    heartRateBPM: workout.heartRateBPM,
                                    elapsedSeconds: workout.elapsedSeconds,
                                    ambientCelsius: viewModel.ambientCelsius,
                                    state: stateOverride ?? workout.status)
    }

    private func compactStatus(_ status: String) -> String {
        switch status {
        case "Phone link ready": "Ready"
        case "Phone linked": "Linked"
        case "Phone link inactive": "Offline"
        case "Phone link failed": "Failed"
        case "Queued for phone": "Queued"
        case "Live weather": "Live"
        case "Manual ambient": "Manual"
        case "Health unavailable": "Unavailable"
        case "Add Health permissions": "Needs Setup"
        case let value where value.hasPrefix("Updated "):
            String(value.dropFirst("Updated ".count))
        default:
            status
        }
    }

    private func metricRow<Accessory: View>(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
            }
            .layoutPriority(1)

            Spacer(minLength: 2)
            accessory()
                .layoutPriority(0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metricRow(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        metricRow(title: title, value: value, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }
}

#Preview {
    ContentView()
}
