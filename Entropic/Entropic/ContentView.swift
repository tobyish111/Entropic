import Charts
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EntropicDashboardViewModel()
    @StateObject private var watchLink = WatchCompanionConnectivity.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    liveWatchCard
                    liveMetricsGrid
                    entropyMeaningCard
                    hourlyChartCard
                    trendChartCard
                    insightsGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(ThermoBackground())
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh entropy data")
                }
            }
            .task {
                await viewModel.start()
            }
            .task {
                await viewModel.runRealtimeLoop()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private var heroCard: some View {
        EntropicCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generated Entropy")
                            .font(.headline)
                        Text("Today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    liveBadge
                }

                Text(viewModel.entropyTodayFormatted)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                HStack(spacing: 10) {
                    Label("Updated \(viewModel.lastUpdatedFormatted)", systemImage: "clock")
                    Spacer(minLength: 8)
                    Label(viewModel.ambientFormatted, systemImage: "cloud.sun.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill((watchLink.snapshot?.isRecent == true || viewModel.status == "Live") ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(watchLink.snapshot?.isRecent == true ? "Watch Live" : viewModel.status)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    @ViewBuilder
    private var liveWatchCard: some View {
        if let snapshot = watchLink.snapshot, snapshot.isRecent {
            EntropicCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        chartHeader(title: "Live Watch Workout", subtitle: snapshot.state, systemImage: "applewatch.watchface")
                        Spacer()
                        Text(snapshot.elapsedFormatted)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.green)
                    }

                    Text(snapshot.entropyFormatted)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        compactMetric(title: "Active", value: snapshot.activeEnergyFormatted, tint: .orange)
                        compactMetric(title: "Basal", value: snapshot.basalEnergyFormatted, tint: .red)
                        compactMetric(title: "Heart", value: snapshot.heartRateFormatted, tint: .pink)
                        compactMetric(title: "Ambient", value: snapshot.ambientFormatted, tint: .cyan)
                    }
                }
            }
        }
    }

    private var liveMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile(title: "Active Heat", value: viewModel.activeEnergyFormatted, systemImage: "flame.fill", tint: .orange)
            metricTile(title: "Basal Heat", value: viewModel.basalEnergyFormatted, systemImage: "heart.fill", tint: .red)
        }
    }

    private var entropyMeaningCard: some View {
        EntropicCard {
            VStack(alignment: .leading, spacing: 12) {
                chartHeader(title: "Universal Effect", subtitle: "Thermodynamic arrow", systemImage: "atom")

                Text("From a microscopic view, entropy tracks how many quantum states could describe the same visible situation. When your metabolism releases heat, that energy disperses into air, clothing, skin, and radiation, increasing the number of possible microscopic arrangements of the environment.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    meaningRow(title: "Today", value: entropyMeaning(for: viewModel.entropyTodayKJPerK))
                    meaningRow(title: "Universe", value: "This is a tiny positive addition to the universe's entropy: useful chemical energy becomes less recoverable environmental heat.")
                    meaningRow(title: "Quantum View", value: "The app does not measure wavefunctions. It estimates the thermodynamic entropy production implied by many microscopic quantum degrees of freedom becoming more dispersed and less reversibly coordinated.")
                }
            }
        }
    }

    private var hourlyChartCard: some View {
        EntropicCard {
            VStack(alignment: .leading, spacing: 12) {
                chartHeader(title: "Real-Time Flow", subtitle: "Last 12 hours", systemImage: "waveform.path.ecg")

                Chart(viewModel.hourlyPoints) { point in
                    BarMark(
                        x: .value("Hour", point.date, unit: .hour),
                        y: .value("Entropy", point.entropyKJPerK)
                    )
                    .foregroundStyle(LinearGradient(colors: [.blue, .green, .yellow, .orange], startPoint: .bottom, endPoint: .top))
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .chartYAxisLabel("kJ/K")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
            }
        }
    }

    private var trendChartCard: some View {
        EntropicCard {
            VStack(alignment: .leading, spacing: 12) {
                chartHeader(title: "Trends", subtitle: "Last 14 days", systemImage: "chart.xyaxis.line")

                Chart(viewModel.dailyPoints) { point in
                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Entropy", point.entropyKJPerK)
                    )
                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.35), .blue.opacity(0.08)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Entropy", point.entropyKJPerK)
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Entropy", point.entropyKJPerK)
                    )
                    .foregroundStyle(.orange)
                }
                .frame(height: 220)
                .chartYAxisLabel("kJ/K")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
            }
        }
    }

    private var insightsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile(title: "14-Day Avg", value: viewModel.fourteenDayAverageFormatted, systemImage: "calendar", tint: .blue)
            metricTile(title: "Trend", value: viewModel.trendDirection, systemImage: "arrow.up.right.circle.fill", tint: .green)
            metricTile(title: "Peak Hour", value: viewModel.peakHourFormatted, systemImage: "bolt.fill", tint: .yellow)
            metricTile(title: "Watch", value: watchLink.status, systemImage: "applewatch", tint: .pink)
        }
    }

    private func entropyMeaning(for entropy: Double?) -> String {
        guard let entropy else { return "No entropy estimate is available yet." }
        switch entropy {
        case ..<5:
            return "A light contribution so far: a small amount of metabolic energy has become dispersed environmental heat."
        case ..<15:
            return "A moderate contribution: your body has measurably increased the environment's thermal disorder today."
        case ..<30:
            return "A high contribution: activity and basal metabolism have pushed substantial heat into surrounding microscopic degrees of freedom."
        default:
            return "A very high contribution: a large amount of chemical free energy has been degraded into broadly dispersed heat."
        }
    }

    private func meaningRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chartHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compactMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metricTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        EntropicCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
