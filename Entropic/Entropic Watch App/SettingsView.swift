import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: EntropyViewModel

    var body: some View {
        Form {
            Section("Environment") {
                VStack(alignment: .leading) {
                    Text("Ambient")
                    Stepper(value: $viewModel.ambientCelsius, in: -20...45, step: 1) {
                        Text("\(viewModel.ambientCelsius, specifier: "%.0f") °C")
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }

            Section("Heat Output") {
                percentageStepper(title: "Active", value: $viewModel.heatFraction)
                percentageStepper(title: "Basal", value: $viewModel.basalHeatFraction)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: viewModel.ambientCelsius) { _, _ in
            refreshToday()
        }
        .onChange(of: viewModel.heatFraction) { _, _ in
            refreshToday()
        }
        .onChange(of: viewModel.basalHeatFraction) { _, _ in
            refreshToday()
        }
    }

    private func percentageStepper(title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...1, step: 0.05) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func refreshToday() {
        Task {
            await viewModel.refreshToday()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: EntropyViewModel())
    }
}
