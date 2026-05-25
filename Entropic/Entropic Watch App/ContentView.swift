import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EntropyViewModel()
    @StateObject private var workout = LiveWorkoutManager()
    @StateObject private var appleWorkout = AppleWorkoutFollower()
    @StateObject private var phoneLink = WatchWorkoutConnectivity.shared

    private var displayedEntropy: Double {
        if workout.hasActiveWorkout {
            return workout.entropyKJPerK(ambientCelsius: viewModel.ambientCelsius,
                                        activeHeatFraction: viewModel.heatFraction,
                                        basalHeatFraction: viewModel.basalHeatFraction)
        }
        if appleWorkout.isFollowing {
            return appleWorkout.entropyKJPerK(ambientCelsius: viewModel.ambientCelsius,
                                             activeHeatFraction: viewModel.heatFraction,
                                             basalHeatFraction: viewModel.basalHeatFraction)
        }
        return viewModel.entropyTodayKJPerK ?? 0
    }

    private var displayedEntropyFormatted: String {
        EntropyCalculator.formatEntropy(displayedEntropy)
    }

    private var activeSessionLabel: String {
        if workout.hasActiveWorkout { return "Live" }
        if appleWorkout.isFollowing { return "Apple" }
        return "Today"
    }

    private var activeElapsedFormatted: String {
        if workout.hasActiveWorkout { return workout.elapsedFormatted }
        if appleWorkout.isFollowing { return appleWorkout.elapsedFormatted }
        return compactStatus(viewModel.lastUpdatedFormatted)
    }

    var body: some View {
        NavigationStack {
            TabView {
                summaryPage
                workoutPage
                statusPage
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(ThermoBackground().ignoresSafeArea())
            .ignoresSafeArea(.container)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.ensureAuthorizedAndRefresh()
            }
            .task {
                await viewModel.runLiveRefreshLoop()
            }
            .task {
                await appleWorkout.runMonitoringLoop()
            }
            .onChange(of: workout.elapsedSeconds) { _, _ in
                sendLiveWorkoutUpdate()
            }
            .onChange(of: workout.status) { _, _ in
                sendLiveWorkoutUpdate()
            }
            .onChange(of: appleWorkout.elapsedSeconds) { _, _ in
                sendLiveWorkoutUpdate()
            }
            .onChange(of: appleWorkout.status) { _, _ in
                sendLiveWorkoutUpdate()
            }
        }
    }

    private var summaryPage: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    summaryHeroSection
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    summaryMetricsSection
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    summaryMeaningSection
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var summaryHeroSection: some View {
        GeometryReader { proxy in
            ZStack {
                entropyCircle
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.44)

                Text("Swipe up for metrics")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .position(x: proxy.size.width / 2, y: max(proxy.size.height - 20, proxy.size.height / 2 + 72))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var workoutPage: some View {
        pageFrame {
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    NavigationLink(destination: workoutDetailView) {
                        statusCircle(title: "Run", value: compactStatus(workout.status), systemImage: "figure.run", tint: workout.hasActiveWorkout ? .green : .orange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: appleWorkoutDetailView) {
                        statusCircle(title: "Apple", value: compactStatus(appleWorkout.status), systemImage: "applewatch", tint: appleWorkout.isFollowing ? .green : .blue)
                    }
                    .buttonStyle(.plain)
                }

                if workout.hasActiveWorkout {
                    HStack(spacing: 7) {
                        controlSquare(systemImage: workout.isPaused ? "play.fill" : "pause.fill", tint: .yellow) {
                            if workout.isPaused {
                                workout.resumeWorkout()
                            } else {
                                workout.pauseWorkout()
                            }
                        }

                        controlSquare(systemImage: "stop.fill", tint: .red) {
                            sendLiveWorkoutUpdate(stateOverride: "Ended")
                            workout.endWorkout()
                        }
                    }
                } else {
                    Button {
                        Task {
                            await viewModel.refreshAmbientTemperature()
                            await workout.startWorkout()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Start")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
    }

    private var summaryMetricsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            summaryHeader(title: "Metrics", subtitle: activeSessionLabel, systemImage: "waveform.path.ecg")

            VStack(spacing: 3) {
                if workout.hasActiveWorkout {
                    rectangleTile(title: "Active", value: workout.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                    rectangleTile(title: "Basal", value: workout.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
                    rectangleTile(title: "Heart", value: workout.heartRateFormatted, systemImage: "heart.circle.fill", tint: .pink)
                    rectangleTile(title: "Air", value: viewModel.ambientTemperatureFormatted, systemImage: "cloud.sun.fill", tint: .cyan)
                } else if appleWorkout.isFollowing {
                    rectangleTile(title: "Active", value: appleWorkout.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                    rectangleTile(title: "Basal", value: appleWorkout.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
                    rectangleTile(title: "Elapsed", value: appleWorkout.elapsedFormatted, systemImage: "timer", tint: .green)
                    rectangleTile(title: "Air", value: viewModel.ambientTemperatureFormatted, systemImage: "cloud.sun.fill", tint: .cyan)
                } else {
                    rectangleTile(title: "Active", value: viewModel.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                    rectangleTile(title: "Basal", value: viewModel.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
                    rectangleTile(title: "Air", value: viewModel.ambientTemperatureFormatted, systemImage: "cloud.sun.fill", tint: .cyan)
                    rectangleTile(title: "Weather", value: compactStatus(viewModel.weatherStatus), systemImage: "location.fill", tint: .blue)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var summaryMeaningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            summaryHeader(title: "Meaning", subtitle: compactEntropyMeaning(for: displayedEntropy), systemImage: "atom")

            NavigationLink(destination: entropyDetailView) {
                rectangleTile(title: "Now", value: displayedEntropyFormatted, systemImage: "atom", tint: .orange)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: entropyMeaningDetailView) {
                rectangleTile(title: "Effect", value: "+S heat dispersal", systemImage: "sparkles", tint: .purple)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: entropyArrowDetailView) {
                rectangleMessage(title: "Arrow", value: "Heat spreads into more states.", tint: .orange)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: entropyCaveatDetailView) {
                rectangleMessage(title: "Caveat", value: "Thermo estimate only.", tint: .blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var statusPage: some View {
        pageFrame {
            LazyVGrid(columns: squareColumns, spacing: 7) {
                squareTile(title: "Update", value: compactStatus(viewModel.lastUpdatedFormatted), systemImage: "arrow.clockwise", tint: .green)
                squareTile(title: "Weather", value: compactStatus(viewModel.weatherStatus), systemImage: "cloud.sun.fill", tint: .cyan)
                squareTile(title: "Phone", value: compactStatus(phoneLink.status), systemImage: "iphone", tint: .blue)
                squareTile(title: "Apple", value: compactStatus(appleWorkout.status), systemImage: "applewatch", tint: appleWorkout.isFollowing ? .green : .blue)
            }
        }
    }

    private var entropyCircle: some View {
        NavigationLink(destination: entropyDetailView) {
            entropyCircleContent
        }
        .buttonStyle(.plain)
    }

    private var entropyCircleContent: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .stroke(AngularGradient(colors: [.blue, .green, .yellow, .orange, .red, .blue], center: .center), lineWidth: 7)
                }
                .shadow(color: .orange.opacity(0.22), radius: 10)

            VStack(spacing: 2) {
                Text(activeSessionLabel.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(activeSessionLabel == "Today" ? Color.secondary : Color.green)
                    .tracking(0.7)
                Text(displayedEntropyFormatted)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                Text(compactEntropyMeaning(for: displayedEntropy))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(width: 126, height: 126)
        .accessibilityLabel(workout.hasActiveWorkout ? "Live workout entropy" : "Entropy today")
        .accessibilityValue(displayedEntropyFormatted)
    }

    private var entropyDetailView: some View {
        detailPage(title: "Entropy", systemImage: "atom", tint: .orange) {
            Text(displayedEntropyFormatted)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            LazyVGrid(columns: squareColumns, spacing: 7) {
                squareTile(title: activeSessionLabel == "Today" ? "Upd" : "Time",
                           value: activeSessionLabel == "Today" ? compactStatus(viewModel.lastUpdatedFormatted) : activeElapsedFormatted,
                           systemImage: activeSessionLabel == "Today" ? "arrow.clockwise" : "timer",
                           tint: .green)
                squareTile(title: "Mode", value: activeSessionLabel, systemImage: "bolt.fill", tint: activeSessionLabel == "Today" ? .orange : .green)
                squareTile(title: "Now", value: compactEntropyMeaning(for: displayedEntropy), systemImage: "sparkles", tint: .purple)
                squareTile(title: "Effect", value: "+S", systemImage: "atom", tint: .orange)
            }

            detailText("This number estimates entropy produced by your body releasing metabolic heat into the environment.")
            detailText("During a workout, higher active energy means more heat flow. More heat flow at the ambient temperature means more entropy production.")
        }
    }

    private var workoutDetailView: some View {
        detailPage(title: "Entropic", systemImage: "figure.run", tint: workout.hasActiveWorkout ? .green : .orange) {
            LazyVGrid(columns: squareColumns, spacing: 7) {
                squareTile(title: "State", value: compactStatus(workout.status), systemImage: "record.circle", tint: workout.hasActiveWorkout ? .green : .orange)
                squareTile(title: "Elapsed", value: workout.elapsedFormatted, systemImage: "timer", tint: .green)
                squareTile(title: "Active", value: workout.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                squareTile(title: "Basal", value: workout.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
            }
        }
    }

    private var appleWorkoutDetailView: some View {
        detailPage(title: "Apple", systemImage: "applewatch", tint: appleWorkout.isFollowing ? .green : .blue) {
            LazyVGrid(columns: squareColumns, spacing: 7) {
                squareTile(title: "State", value: compactStatus(appleWorkout.status), systemImage: "record.circle", tint: appleWorkout.isFollowing ? .green : .blue)
                squareTile(title: "Elapsed", value: appleWorkout.elapsedFormatted, systemImage: "timer", tint: .green)
                squareTile(title: "Active", value: appleWorkout.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
                squareTile(title: "Basal", value: appleWorkout.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
            }
        }
    }

    private var entropyMeaningDetailView: some View {
        detailPage(title: "Effect", systemImage: "sparkles", tint: .purple) {
            squareTile(title: "Universe", value: "+S", systemImage: "sparkles", tint: .purple)
            detailText("Entropy is the count of possible microscopic arrangements that match what we see at human scale.")
            detailText("Workout heat adds a tiny positive amount to the universe's entropy as ordered chemical energy becomes dispersed thermal motion.")
        }
    }

    private var entropyArrowDetailView: some View {
        detailPage(title: "Arrow", systemImage: "arrow.down", tint: .orange) {
            squareTile(title: "Direction", value: "Forward", systemImage: "arrow.right", tint: .orange)
            detailText("The arrow of time points toward states where energy is more spread out and less available to do useful work.")
            detailText("In a workout, ATP and food energy become muscle work and heat. The heat disperses into skin, air, clothing, and radiation.")
        }
    }

    private var entropyCaveatDetailView: some View {
        detailPage(title: "Caveat", systemImage: "exclamationmark.triangle", tint: .blue) {
            squareTile(title: "Model", value: "Estimate", systemImage: "atom", tint: .blue)
            detailText("Entropic estimates thermodynamic entropy from Health energy and ambient temperature. It is not measuring quantum states directly.")
            detailText("For workouts, use it as a physical interpretation of metabolic heat, not as a medical score or a precise lab calorimetry result.")
        }
    }

    private var squareColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]
    }

    private func pageFrame<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            content()
                .padding(.horizontal, 7)
                .padding(.top, 5)
                .padding(.bottom, 12)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func detailPage<Content: View>(title: String, systemImage: String, tint: Color, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    content()
                }
                .padding(.horizontal, 7)
                .padding(.top, 5)
                .padding(.bottom, 12)
                .frame(width: proxy.size.width, alignment: .top)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(ThermoBackground())
        .navigationTitle(title)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summaryHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func rectangleTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.52)
                .allowsTightening(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(tint.opacity(0.7))
                .frame(width: 5)
        }
    }

    private func rectangleMessage(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func squareTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(tint.opacity(0.7))
                .frame(width: 10, height: 10)
                .padding(7)
        }
    }

    private func statusCircle(title: String, value: String, systemImage: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.75), lineWidth: 4)
                }

            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }
            .padding(9)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    private func controlSquare(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private func squareMessage(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer()
                Rectangle()
                    .fill(tint.opacity(0.75))
                    .frame(width: 9, height: 9)
            }
            Text(value)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        guard workout.hasActiveWorkout || appleWorkout.isFollowing || stateOverride == "Ended" else { return }

        let activeKcal = workout.hasActiveWorkout ? workout.activeEnergyKcal : appleWorkout.activeEnergyKcal
        let basalKcal = workout.hasActiveWorkout ? workout.basalEnergyKcal : appleWorkout.basalEnergyKcal
        let heartRate = workout.hasActiveWorkout ? workout.heartRateBPM : nil
        let elapsed = workout.hasActiveWorkout ? workout.elapsedSeconds : appleWorkout.elapsedSeconds
        let state = stateOverride ?? (workout.hasActiveWorkout ? workout.status : appleWorkout.status)

        phoneLink.sendWorkoutUpdate(entropyKJPerK: displayedEntropy,
                                    activeKcal: activeKcal,
                                    basalKcal: basalKcal,
                                    heartRateBPM: heartRate,
                                    elapsedSeconds: elapsed,
                                    ambientCelsius: viewModel.ambientCelsius,
                                    state: state)
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
        case "Apple Idle": "Idle"
        case "Apple Watch": "Watch"
        case "Apple Live": "Live"
        case "Apple Ended": "Ended"
        case "Apple Off": "Off"
        case let value where value.hasPrefix("Updated "):
            String(value.dropFirst("Updated ".count))
        default:
            status
        }
    }
}

#Preview {
    ContentView()
}
