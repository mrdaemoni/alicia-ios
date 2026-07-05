import SwiftUI

/// Alicia's vitals — an engraved page, not a dashboard. Mono-caps labels,
/// serif values, and hand-wobbled ink strokes for the bars, headed by a
/// stippled form that regenerates each day.
/// Lives inside Home's NavigationStack (pushed from the status strip), so
/// it deliberately has no NavigationStack of its own.
struct HealthView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StippleIllustration()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                Text("HER VITALS")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .tracking(2.2)
                    .foregroundStyle(Theme.inkSoft)

                Text(verdict)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(store.health) { InkMetricRow(metric: $0) }
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
        .refreshable { await store.load() }
        .sectionBackground()
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var verdict: String {
        let values = store.health.map(\.value)
        guard !values.isEmpty else { return "Listening for her pulse…" }
        let mean = values.reduce(0, +) / Double(values.count)
        switch mean {
        case 0.85...: return "She is running clear."
        case 0.6...:  return "Steady, with some weather."
        default:      return "Something needs a look."
        }
    }
}

/// One vital: mono-caps name, serif value, and the measure drawn as a
/// hand-wobbled ink stroke over a faint full-length track.
struct InkMetricRow: View {
    let metric: HealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.name.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(metric.display)
                    .font(.system(.callout, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            InkStroke(fraction: metric.value, seed: metric.name.hashValue)
                .frame(height: 10)
        }
    }
}

/// A single ink line whose length is the value — drawn with a slight
/// vertical wobble so it reads as a pen stroke, not a progress bar.
struct InkStroke: View {
    var fraction: Double
    var seed: Int

    var body: some View {
        Canvas { context, size in
            var state = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 13)
            func rnd() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            let midY = size.height / 2
            // Faint full track — the field the stroke lives in.
            var track = Path()
            track.move(to: CGPoint(x: 0, y: midY))
            track.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(track, with: .color(Theme.ink.opacity(0.12)), lineWidth: 0.8)

            // The stroke itself, wobbling like a held pen.
            let endX = size.width * max(0.02, min(1, fraction))
            let segments = 14
            var stroke = Path()
            stroke.move(to: CGPoint(x: 0, y: midY + (rnd() - 0.5) * 2))
            for i in 1...segments {
                let x = endX * Double(i) / Double(segments)
                let y = midY + (rnd() - 0.5) * 3.2
                stroke.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(stroke, with: .color(Theme.ink.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round,
                                              lineJoin: .round))
            // A small terminal tick, like closing a measurement.
            var tick = Path()
            tick.move(to: CGPoint(x: endX, y: midY - 4))
            tick.addLine(to: CGPoint(x: endX, y: midY + 4))
            context.stroke(tick, with: .color(Theme.ink.opacity(0.85)), lineWidth: 1.6)
        }
    }
}

#Preview {
    NavigationStack {
        HealthView()
            .environment(AppStore(service: MockAliciaService()))
            .tint(Theme.accent)
    }
}
