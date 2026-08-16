#if DEBUG
import SwiftUI

/// A private tuning room for procedural representations. Nothing here is
/// reachable in Release builds; approved pieces move into a product surface.
struct MotionLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var voice: AliciaPresence.Voice = .ariadne
    @State private var state: AliciaPresence.State = .listening
    @State private var attention = 0.72
    @State private var isPlaying = true
    @State private var phase = 4.2
    @State private var focus: UnitPoint?
    @State private var showsConstruction = false
    @State private var previewsReduceMotion = false
    @State private var auditReport: String?
    private let runsAuditOnLaunch: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let voiceArgument = arguments.first { $0.hasPrefix("--presence-voice=") }
            .map { String($0.dropFirst("--presence-voice=".count)) }
        let stateArgument = arguments.first { $0.hasPrefix("--presence-state=") }
            .map { String($0.dropFirst("--presence-state=".count)) }
        let attentionArgument = arguments.first { $0.hasPrefix("--presence-attention=") }
            .map { String($0.dropFirst("--presence-attention=".count)) }

        _voice = State(initialValue: voiceArgument
            .flatMap(AliciaPresence.Voice.init(rawValue:)) ?? .ariadne)
        _state = State(initialValue: AliciaPresence.State.allCases.first {
            $0.rawValue.lowercased() == stateArgument?.lowercased()
        } ?? .listening)
        _attention = State(initialValue: min(1, max(0,
            attentionArgument.flatMap(Double.init) ?? 0.72
        )))
        _previewsReduceMotion = State(initialValue:
            arguments.contains("--presence-reduce-motion"))
        runsAuditOnLaunch = arguments.contains("--presence-audit")
    }

    private var metrics: AliciaPresence.Metrics {
        AliciaPresence.metrics(for: voice, state: state, attention: attention)
    }

    private var currentAudit: AliciaPresence.Audit {
        AliciaPresence.audit(voice: voice, state: state, attention: attention,
                             phase: isPlaying ? 4.2 : phase, focus: focus)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    AliciaPresence(
                        voice: voice,
                        state: state,
                        attention: attention,
                        focus: focus,
                        phase: isPlaying ? nil : phase,
                        showsConstruction: showsConstruction,
                        previewsReduceMotion: previewsReduceMotion
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DRAG TO MOVE HER ATTENTION")
                        Text("\(voice.name) · \(voice.role)")
                            .foregroundStyle(Theme.ink)
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.4)
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
            .task {
                if runsAuditOnLaunch { runAudit() }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MOTION LAB · PRESENCE 002")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(1.5)
                Spacer()
                Button(isPlaying ? "PAUSE" : "PLAY") { isPlaying.toggle() }
                    .labButton()
                Button("RESET") { reset() }
                    .labButton()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(AliciaPresence.Voice.allCases) { option in
                        choiceButton(option.name, selected: voice == option) {
                            voice = option
                            auditReport = nil
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                ForEach(AliciaPresence.State.allCases) { option in
                    choiceButton(option.rawValue, selected: state == option) {
                        state = option
                        auditReport = nil
                    }
                }
            }

            labSlider("ATTENTION", value: $attention, range: 0...1,
                      valueText: "\(Int((attention * 100).rounded()))%")

            if !isPlaying {
                labSlider("PHASE", value: $phase, range: 0...20,
                          valueText: phase.formatted(.number.precision(.fractionLength(2))))
            }

            HStack {
                Toggle("REDUCE MOTION", isOn: $previewsReduceMotion)
                Toggle("SHOW MATH", isOn: $showsConstruction)
            }
            .font(.system(size: 9, design: .monospaced))
            .tracking(1)
            .tint(Theme.accent)

            HStack(spacing: 7) {
                Text(performanceLine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button("AUDIT ALL") { runAudit() }
                    .labButton()
            }
            .font(.system(size: 8, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(currentAudit.isSafe ? Theme.inkSoft : Theme.rose)

            if let auditReport {
                Text(auditReport)
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(auditReport.hasPrefix("PASS")
                                     ? Theme.inkSoft : Theme.rose)
            }
        }
    }

    private var performanceLine: String {
        let visible = Int((currentAudit.visibleFraction * 100).rounded())
        let finite = currentAudit.finite == currentAudit.total ? "FINITE" : "NONFINITE"
        return String(format: "%.2f TEMPO · %d PTS · %d FPS · %d%% VISIBLE · %@",
                      metrics.tempo, metrics.pointCount, metrics.framesPerSecond,
                      visible, finite)
    }

    private func choiceButton(_ label: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 9, design: .monospaced).weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(selected ? Theme.paper : Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(selected ? Theme.ink : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(Theme.ink.opacity(0.28), lineWidth: 0.7))
    }

    private func labSlider(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, valueText: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 74, alignment: .leading)
            Slider(value: value, in: range)
            Text(valueText)
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Theme.inkSoft)
    }

    private func runAudit() {
        let summary = AliciaPresence.auditAll(attention: attention)
        let visible = Int((summary.lowestVisibleFraction * 100).rounded())
        auditReport = summary.isSafe
            ? "PASS · \(summary.combinations) COMBINATIONS · LOWEST \(visible)% VISIBLE"
            : "FAIL · \(summary.failures) OF \(summary.combinations) COMBINATIONS"
    }

    private func reset() {
        voice = .ariadne
        state = .listening
        attention = 0.72
        isPlaying = true
        phase = 4.2
        focus = nil
        showsConstruction = false
        previewsReduceMotion = false
        auditReport = nil
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
