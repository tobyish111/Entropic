import SwiftUI

struct ThermoBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.25), Color.red.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(gradient: Gradient(colors: [Color.orange.opacity(0.35), .clear]), center: .center, startRadius: 10, endRadius: 280)
            FluidNoise()
                .blendMode(.overlay)
                .opacity(0.6)
        }
        .ignoresSafeArea()
    }
}

/// A simple fluid noise layer to evoke thermodynamic turbulence.
struct FluidNoise: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let count = 5
                for i in 0..<count {
                    let t = CGFloat(time / 6.0 + Double(i) * 0.6)
                    let x = sin(t * 1.3) * w * 0.3 + w * 0.5
                    let y = cos(t * 0.9) * h * 0.3 + h * 0.5
                    let rect = CGRect(x: x - 120, y: y - 120, width: 240, height: 240)
                    let color = Color(hue: Double((t.truncatingRemainder(dividingBy: 1) + CGFloat(i) * 0.1)).truncatingRemainder(dividingBy: 1), saturation: 0.4, brightness: 0.9)
                    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color.opacity(0.25), .clear]), center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 10, endRadius: 120))
                }
            }
        }
    }
}

struct ThermoGaugeView: View {
    var value: Double
    var target: Double
    var unit: String

    var body: some View {
        Gauge(value: min(value, target), in: 0...target) {
            Text("Entropy")
        } currentValueLabel: {
            Text(String(format: "%.1f", value))
                .contentTransition(.numericText())
        } minimumValueLabel: {
            Text("0")
        } maximumValueLabel: {
            Text(String(format: "%.0f", target))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.blue, .green, .yellow, .orange, .red]))
        .overlay(alignment: .bottom) {
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}
