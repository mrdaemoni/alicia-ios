#if DEBUG
import SwiftUI

/// A private tuning room for procedural representations. Nothing here is
/// reachable in Release builds; approved pieces move into a product surface.
struct MotionLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state: AliciaPresence.State = .resting
    @State private var isPlaying = true
    @State private var phase = 0.0
    @State private var speed = 1.0
    @State private var complexity = 12.0
    @State private var focus: UnitPoint?
    @State private var showsConstruction = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    AliciaPresence(
                        state: state,
                        speed: speed,
                        complexity: Int(complexity),
                        focus: focus,
                        phase: isPlaying ? nil : phase,
                        showsConstruction: showsConstruction
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                focus = UnitPoint(
                                    x: min(1, max(0, value.location.x / proxy.size.width)),
                                    y: min(1, max(0, value.location.y / proxy.size.height))
                                )
                            }
                    )
                }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    Text("DRAG TO MOVE HER ATTENTION")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(14)
                }

                controls
                    .padding(16)
                    .background(Theme.paper.opacity(0.96))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.ink.opacity(0.2)).frame(height: 0.7)
                    }
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                Button("CLOSE") { dismiss() }
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.ink)
                    .padding(16)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("MOTION LAB · PRESENCE 001")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(1.5)
                Spacer()
                Button(isPlaying ? "PAUSE" : "PLAY") { isPlaying.toggle() }
                    .labButton()
                Button("RESET") { reset() }
                    .labButton()
            }

            HStack(spacing: 7) {
                ForEach(AliciaPresence.State.allCases) { option in
                    Button(option.rawValue) { state = option }
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(state == option ? Theme.paper : Theme.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(state == option ? Theme.ink : Color.clear,
                                    in: Capsule())
                        .overlay(Capsule().stroke(Theme.ink.opacity(0.28), lineWidth: 0.7))
                }
            }

            if !isPlaying {
                labSlider("PHASE", value: $phase, range: 0...20,
                          valueText: phase.formatted(.number.precision(.fractionLength(2))))
            }
            labSlider("SPEED", value: $speed, range: 0.2...2,
                      valueText: speed.formatted(.number.precision(.fractionLength(2))))
            labSlider("LINES", value: $complexity, range: 5...20,
                      valueText: "\(Int(complexity))")

            Toggle("SHOW THE MATH", isOn: $showsConstruction)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.2)
                .tint(Theme.accent)
        }
    }

    private func labSlider(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, valueText: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 46, alignment: .leading)
            Slider(value: value, in: range)
            Text(valueText)
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Theme.inkSoft)
    }

    private func reset() {
        state = .resting
        isPlaying = true
        phase = 0
        speed = 1
        complexity = 12
        focus = nil
        showsConstruction = false
    }
}

private extension View {
    func labButton() -> some View {
        font(.system(size: 9, design: .monospaced).weight(.semibold))
            .tracking(1)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .overlay(Capsule().stroke(Theme.ink.opacity(0.3), lineWidth: 0.7))
    }
}

#Preview("Motion Lab") {
    MotionLabView()
        .preferredColorScheme(.light)
}
#endif
