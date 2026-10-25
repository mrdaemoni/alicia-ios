#if DEBUG
import SwiftUI

struct RelationalPresence: View {
    var motion: RelationalMotion
    var isActive = true
    var previewReduction = false
    @Environment(\.accessibilityReduceMotion) private var reduction
    @Environment(\.scenePhase) private var scene
    var body: some View {
        let reduced = reduction || previewReduction
        TimelineView(.animation(minimumInterval: 1.0/30, paused: reduced || !isActive || scene != .active)) { _ in
            let frame = motion.frame(now: ProcessInfo.processInfo.systemUptime, reduced: reduced)
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let points = RelationalGeometry.positions(frame, size: size)
                let dot = max(0.7, min(1.1, min(size.width*0.94, size.height*1.12)/470))
                for bucket in 0..<3 {
                    var path = Path()
                    for (p, index) in points where index % 3 == bucket {
                        path.addRect(CGRect(x: p.x, y: p.y, width: dot, height: dot))
                    }
                    context.fill(path, with: .color(Theme.ink.opacity([0.3,0.51,0.76][bucket])))
                }
            }
        }
        .accessibilityLabel("Alicia’s live presence")
    }
}
#endif
