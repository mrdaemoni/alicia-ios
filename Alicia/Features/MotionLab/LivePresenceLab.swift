#if DEBUG
import SwiftUI

/// The shared candidate in a review room. Fixture mode never publishes status.
struct LivePresenceLab: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fixtureMotion = RelationalMotion(now: ProcessInfo.processInfo.systemUptime)
    @State private var activity = "listening"
    @State private var stance = "witness"
    private let fixture = ProcessInfo.processInfo.arguments.contains("--live-presence-fixture")
    private var client: LivePresenceClient { .shared }

    init() {
        let args = ProcessInfo.processInfo.arguments
        _activity = State(initialValue: args.first { $0.hasPrefix("--presence-state=") }
            .map { String($0.dropFirst("--presence-state=".count)).lowercased() } ?? "listening")
        _stance = State(initialValue: args.first { $0.hasPrefix("--presence-stance=") }
            .map { String($0.dropFirst("--presence-stance=".count)) } ?? "witness")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(fixture ? "PRESENCE · FIXTURE" : "PRESENCE · LIVE CANDIDATE")
                Spacer()
                Button("CLOSE") { dismiss() }
            }
            .font(.system(size: 10, design: .monospaced))
            RelationalPresence(motion: fixture ? fixtureMotion : client.motion,
                previewReduction: ProcessInfo.processInfo.arguments.contains("--presence-reduce-motion"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if fixture {
                Picker("Activity", selection: $activity) {
                    ForEach(["resting", "listening", "thinking", "speaking"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Stance", selection: $stance) {
                    ForEach(["witness", "ask", "offer", "hold", "celebrate", "challenge"], id: \.self) { Text($0).tag($0) }
                }
                Text("Synthetic review signals. No microphone or status publishing.")
            } else {
                Toggle("Use live presence in this debug session", isOn: Binding(get: { client.enabled }, set: { client.setEnabled($0) }))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let fact = client.fact
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(fact.activity) · \(fact.source)")
                        Text("\(fact.expression.stance) · \(fact.expression.source)")
                    }
                }
                Text("Listening follows actual phone capture. Thinking follows reply preparation. Emotional stance is interpreted from Alicia’s awareness. Opening this room never opens a microphone.")
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.ink)
        .padding(24)
        .background(Theme.backdrop.ignoresSafeArea())
        .task { if fixture { retargetFixture() } }
        .onChange(of: activity) { _, _ in retargetFixture() }
        .onChange(of: stance) { _, _ in retargetFixture() }
    }

    private func retargetFixture() {
        guard fixture else { return }
        var fact = LivePresenceFact()
        fact.activity = activity; fact.remainingMS = 8000
        fact.expression.stance = stance
        fact.level = activity == "listening" ? 0.36 : 0
        fixtureMotion.update(fact, now: ProcessInfo.processInfo.systemUptime)
    }
}
#endif
