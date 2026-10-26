import SwiftUI

struct RelationalPresence: View {
    var motion: RelationalMotion
    var isActive = true
    var previewReduction = false
    var playbackLevel: (() -> Double?)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduction
    @Environment(\.scenePhase) private var scene
#if DEBUG
    private let profiles = ProcessInfo.processInfo.arguments.contains("--live-presence-profile")
#endif
    var body: some View {
        let reduced = reduction || previewReduction
        TimelineView(.animation(minimumInterval: 1.0/30, paused: reduced || !isActive || scene != .active)) { _ in
            let frame: RelationalGeometry.Frame = {
                var value = motion.frame(now: ProcessInfo.processInfo.systemUptime, reduced: reduced)
                if !reduced, let level = playbackLevel?() { value.parameters.level = level }
                return value
            }()
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
#if DEBUG
                let started = ProcessInfo.processInfo.systemUptime
#endif
                let points = RelationalGeometry.positions(frame, size: size)
                let dot = max(0.7, min(1.1, min(size.width*0.94, size.height*1.12)/470))
                for bucket in 0..<3 {
                    var path = Path()
                    for (p, index) in points where index % 3 == bucket {
                        path.addRect(CGRect(x: p.x, y: p.y, width: dot, height: dot))
                    }
                    context.fill(path, with: .color(Theme.ink.opacity([0.3,0.51,0.76][bucket])))
                }
#if DEBUG
                if profiles { RelationalRenderAudit.shared.record((ProcessInfo.processInfo.systemUptime-started)*1000) }
#endif
            }
#if DEBUG
            .overlay(alignment: .topLeading) {
                if profiles {
                    Text(RelationalRenderAudit.shared.summary)
                        .font(.system(size: 9, design: .monospaced))
                        .accessibilityIdentifier("presence.debug.metrics")
                }
            }
#endif
        }
        .accessibilityLabel("Alicia’s live presence")
    }
}

#if DEBUG
/// CPU command preparation only. Does not measure GPU/frame delivery or energy.
private final class RelationalRenderAudit: @unchecked Sendable {
    static let shared = RelationalRenderAudit()
    private let lock = NSLock()
    private var samples: [Double] = []
    private var result = "CPU samples 0/180"
    var summary: String { lock.lock(); defer { lock.unlock() }; return result }
    func record(_ milliseconds: Double) {
        lock.lock(); defer { lock.unlock() }
        guard samples.count < 180 else { return }
        samples.append(milliseconds)
        if samples.count == 180 {
            let ordered = samples.sorted()
            result = String(format: "CPU 180 samples · median %.2f ms · p95 %.2f ms", ordered[90], ordered[171])
            print("PRESENCE_RENDER_AUDIT " + result)
        } else { result = "CPU samples \(samples.count)/180" }
    }
}
#endif
