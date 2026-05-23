import SwiftUI

struct ThermoBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.18), Color.red.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(gradient: Gradient(colors: [Color.orange.opacity(0.28), .clear]), center: .topTrailing, startRadius: 20, endRadius: 420)
            FluidNoise()
                .blendMode(.overlay)
                .opacity(0.45)
        }
        .ignoresSafeArea()
    }
}

struct FluidNoise: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = 7

                for index in 0..<count {
                    let phase = CGFloat(time / 7.0 + Double(index) * 0.52)
                    let x = sin(phase * 1.2) * size.width * 0.35 + size.width * 0.5
                    let y = cos(phase * 0.82) * size.height * 0.3 + size.height * 0.48
                    let diameter = min(size.width, size.height) * 0.72
                    let rect = CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
                    let hue = Double((phase.truncatingRemainder(dividingBy: 1) + CGFloat(index) * 0.08).truncatingRemainder(dividingBy: 1))
                    let color = Color(hue: hue, saturation: 0.45, brightness: 0.95)

                    context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color.opacity(0.18), .clear]), center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 10, endRadius: diameter / 2))
                }
            }
        }
    }
}

struct EntropicCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
