import SwiftUI

/// A mathematical body for Alicia: nested, continuous ink contours around
/// a small moving center. It is deliberately a reusable design-system view,
/// while the controls used to tune it live in the DEBUG-only Motion Lab.
struct AliciaPresence: View {
    enum State: String, CaseIterable, Identifiable {
        case resting = "RESTING"
        case listening = "LISTENING"
        case thinking = "THINKING"

        var id: String { rawValue }

        fileprivate var motion: Motion {
            switch self {
            case .resting:
                Motion(speed: 0.34, breath: 0.035, ripple: 0.030,
                       asymmetry: 0.025, orbit: 0.18)
            case .listening:
                Motion(speed: 0.62, breath: 0.050, ripple: 0.055,
                       asymmetry: 0.065, orbit: 0.28)
            case .thinking:
                Motion(speed: 1.0, breath: 0.065, ripple: 0.090,
                       asymmetry: 0.105, orbit: 0.42)
            }
        }
    }

    fileprivate struct Motion {
        let speed: Double
        let breath: Double
        let ripple: Double
        let asymmetry: Double
        let orbit: Double
    }

    var state: State = .resting
    var speed: Double = 1
    var complexity: Int = 12
    /// A normalized point that gently pulls the body toward attention.
    var focus: UnitPoint?
    /// Set this for deterministic stills and phase-by-phase inspection.
    var phase: Double?
    var showsConstruction = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: phase != nil || reduceMotion)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, date: timeline.date)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alicia, \(state.rawValue.lowercased())")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let motion = state.motion
        let clock = phase ?? date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 10_000)
        let t = clock * motion.speed * speed
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.49)
        let radius = min(size.width, size.height) * 0.32
        let focusPoint = focus.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }

        if showsConstruction {
            drawConstruction(in: &context, size: size, center: center,
                             radius: radius, focus: focusPoint)
        }

        let count = max(5, min(20, complexity))
        for shell in 0..<count {
            let progress = Double(shell) / Double(max(1, count - 1))
            let shellRadius = radius * (0.25 + progress * 0.78)
            let alpha = 0.16 + (1 - progress) * 0.22
            let path = contour(center: center, radius: shellRadius,
                               time: t, shell: shell, motion: motion,
                               focus: focusPoint)
            context.stroke(
                path,
                with: .color(Theme.ink.opacity(alpha)),
                style: StrokeStyle(lineWidth: shell % 4 == 0 ? 1.15 : 0.72,
                                   lineCap: .round, lineJoin: .round)
            )
        }

        drawOrbit(in: &context, center: center, radius: radius,
                  time: t, motion: motion)
    }

    private func contour(center: CGPoint, radius: Double, time: Double,
                         shell: Int, motion: Motion, focus: CGPoint?) -> Path {
        var path = Path()
        let samples = 144
        let shellPhase = Double(shell) * 0.37
        let breath = 1 + sin(time * 1.25 + shellPhase * 0.18) * motion.breath

        for sample in 0...samples {
            let theta = Double(sample) / Double(samples) * 2 * Double.pi
            let three = sin(theta * 3 + time * 0.72 + shellPhase)
            let five = sin(theta * 5 - time * 0.41 - shellPhase * 0.6)
            let slow = cos(theta * 2 - time * 0.23 + shellPhase)
            let noise = three * motion.ripple
                + five * motion.ripple * 0.58
                + slow * motion.asymmetry
            let r = radius * breath * (1 + noise)

            // A slight vertical stretch keeps the result bodily rather than
            // reading as another ripple or sonar field.
            var point = CGPoint(
                x: center.x + cos(theta) * r * 0.86,
                y: center.y + sin(theta) * r * 1.12
            )
            if let focus {
                point = pulled(point, toward: focus, radius: radius,
                               amount: state == .listening ? 0.12 : 0.065)
            }
            if sample == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func pulled(_ point: CGPoint, toward focus: CGPoint,
                        radius: Double, amount: Double) -> CGPoint {
        let dx = focus.x - point.x
        let dy = focus.y - point.y
        let distance = max(1, hypot(dx, dy))
        let influence = min(1, radius * 1.8 / distance) * amount
        return CGPoint(x: point.x + dx * influence,
                       y: point.y + dy * influence)
    }

    private func drawOrbit(in context: inout GraphicsContext, center: CGPoint,
                           radius: Double, time: Double, motion: Motion) {
        let orbitRadius = radius * motion.orbit
        for index in 0..<5 {
            let offset = Double(index) * 2 * Double.pi / 5
            let angle = time * (0.38 + Double(index) * 0.025) + offset
            let point = CGPoint(
                x: center.x + cos(angle) * orbitRadius,
                y: center.y + sin(angle) * orbitRadius * 0.58
            )
            let dotRadius = index == 0 ? 2.2 : 1.25
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - dotRadius,
                                      y: point.y - dotRadius,
                                      width: dotRadius * 2,
                                      height: dotRadius * 2)),
                with: .color(Theme.ink.opacity(index == 0 ? 0.78 : 0.42))
            )
        }
    }

    private func drawConstruction(in context: inout GraphicsContext, size: CGSize,
                                  center: CGPoint, radius: Double, focus: CGPoint?) {
        var axes = Path()
        axes.move(to: CGPoint(x: center.x, y: center.y - radius * 1.25))
        axes.addLine(to: CGPoint(x: center.x, y: center.y + radius * 1.25))
        axes.move(to: CGPoint(x: center.x - radius, y: center.y))
        axes.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        context.stroke(axes, with: .color(Theme.accent.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))

        if let focus {
            var line = Path()
            line.move(to: center)
            line.addLine(to: focus)
            context.stroke(line, with: .color(Theme.rose.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 0.7, dash: [2, 4]))
            context.stroke(Path(ellipseIn: CGRect(x: focus.x - 7, y: focus.y - 7,
                                                  width: 14, height: 14)),
                           with: .color(Theme.rose.opacity(0.55)), lineWidth: 0.8)
        }
    }
}

#Preview("Alicia Presence") {
    AliciaPresence(state: .thinking, complexity: 14,
                   focus: UnitPoint(x: 0.72, y: 0.32), phase: 4.2)
        .frame(width: 360, height: 520)
        .background(Theme.backdrop)
        .preferredColorScheme(.light)
}
