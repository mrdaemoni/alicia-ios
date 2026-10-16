import SwiftUI

/// Higher · Lower · Again for the morning briefing, in quiet ink small caps
/// (CL-20261015-steerable-briefing). Words, never glyphs: no SF Symbols and
/// no emoji. The same panel sits in the reading bar (ink ground) and the
/// immersive reader (paper ground). It shows only what applies right now:
/// during a during week the three commands while it plays; in an after week
/// the same three once it ends; Landed / Didn't land at the end in both.
struct BriefingSteeringPanel: View {
    @Environment(AppStore.self) private var store
    var onInk = false

    private var ink: Color { onInk ? Theme.paper : Theme.ink }
    private var soft: Color { onInk ? Theme.paper.opacity(0.6) : Theme.inkSoft }

    var body: some View {
        let steering = store.briefingSteering
        let reader = store.reader
        if steering.isCurrent(reader), let info = steering.steering, info.enabled {
            VStack(alignment: .leading, spacing: 6) {
                if steering.controlsVisible(reader) {
                    HStack(spacing: 0) {
                        command(.higher, label: "Higher, more general")
                        dot
                        command(.lower, label: "Lower, more concrete")
                        dot
                        command(.again, label: "Again, replay the sentence")
                        Spacer(minLength: 6)
                        Text(info.armLabel)
                            .font(.system(size: 8, design: .monospaced).weight(.semibold)).tracking(1.2)
                            .foregroundStyle(soft).lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityIdentifier("steer.arm")
                    }
                } else if !steering.ended {
                    Text(info.armLabel)
                        .font(.system(size: 8, design: .monospaced).weight(.semibold)).tracking(1.2)
                        .foregroundStyle(soft).accessibilityIdentifier("steer.arm")
                }
                if let line = steering.line {
                    Text(line)
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("steer.line")
                        .transition(.opacity)
                }
                if steering.endCheckVisible(reader) { BriefingEndCheck(onInk: onInk) }
#if DEBUG
                if BriefingSteeringPreview.liveAudio {
                    // What the phone believes actually played, for the live-audio UI test.
                    Text(steering.heardPath.map { "\($0.segment_id)·\($0.level)·\($0.from_sentence_index)" }.joined(separator: " > "))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(soft)
                        .accessibilityIdentifier("steer.debug.path")
                    Text(steering.heardPath.map { String(format: "%.1f", $0.seconds) }.joined(separator: " "))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(soft)
                        .accessibilityIdentifier("steer.debug.seconds")
                }
#endif
            }
            .animation(.easeOut(duration: 0.2), value: steering.line)
        }
    }

    private var dot: some View {
        Text("·").font(.system(size: 11, design: .monospaced)).foregroundStyle(soft)
            .padding(.horizontal, 4).accessibilityHidden(true)
    }

    private func command(_ command: SteerCommand, label: String) -> some View {
        let busy = store.briefingSteering.busy
        return Button { store.briefingSteering.steer(command) } label: {
            VStack(spacing: 2) {
                Text(command.title)
                    .font(.system(size: 10, design: .monospaced).weight(.bold)).tracking(1.6)
                    .foregroundStyle(ink.opacity(busy ? 0.45 : 1))
                InkUnderline(color: ink.opacity(0.7), seed: command.rawValue.inkSeed, lineWidth: 1)
                    .frame(width: 34, height: 3)
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(label)
        .accessibilityIdentifier("steer." + command.rawValue)
    }
}

/// The end-of-briefing check, identical in both arms. A verdict is bound to
/// the path actually heard; it carries no words and never reaches tomorrow.
struct BriefingEndCheck: View {
    @Environment(AppStore.self) private var store
    var onInk = false

    var body: some View {
        let steering = store.briefingSteering
        VStack(alignment: .leading, spacing: 6) {
            Text("DID IT LAND?")
                .font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(1.5)
                .foregroundStyle(onInk ? Theme.paper.opacity(0.6) : Theme.inkSoft)
            HStack(spacing: 10) {
                choice("Landed", verdict: "landed", id: "steer.landed")
                choice("Didn't land", verdict: "didnt_land", id: "steer.didntLand")
            }
            if !steering.verdictNotice.isEmpty {
                Text(steering.verdictNotice)
                    .font(.system(size: 11, design: .serif).italic())
                    .foregroundStyle(onInk ? Theme.paper.opacity(0.75) : Theme.inkSoft)
                    .accessibilityIdentifier("steer.verdictNotice")
            }
        }
    }

    private func choice(_ title: String, verdict: String, id: String) -> some View {
        let selected = store.briefingSteering.savedVerdict == verdict
        let ground = onInk ? Theme.paper : Theme.ink
        return Button { store.briefingSteering.verdict(verdict == "landed") } label: {
            Text(title).font(.system(.subheadline, design: .serif))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .foregroundStyle(selected ? (onInk ? Theme.ink : Theme.paper) : ground)
                .background(selected ? ground : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(ground.opacity(selected ? 1 : 0.3), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .disabled(store.briefingSteering.busy || store.briefingSteering.savedVerdict != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// On the briefing card: which week this is, and the v1.1 headphone setting.
struct BriefingSteeringSettings: View {
    @Environment(AppStore.self) private var store
    let briefing: MorningBriefing

    var body: some View {
        if briefing.isSteerable, let info = briefing.steering {
            InkDisclosure("Steering this briefing") {
                Text(info.arm == "after"
                     ? "This week, Higher, Lower and Again appear when the briefing ends. Higher or Lower plays it again at that level."
                     : "While it plays, Higher says the rest more generally, Lower more concretely, and Again replays the sentence. What you've heard stays as it was.")
                    .font(.system(.footnote, design: .serif)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.armLabel)
                    .font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(1.4)
                    .foregroundStyle(Theme.inkSoft).accessibilityIdentifier("morningBriefing.steerArm")
                let on = store.briefingSteering.remoteSteering
                Button { store.briefingSteering.remoteSteering.toggle() } label: {
                    HStack(spacing: 8) {
                        Text("HEADPHONE NEXT / PREVIOUS = HIGHER / LOWER")
                            .font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(1.2)
                            .foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(on ? "ON" : "OFF")
                            .font(.system(size: 10, design: .monospaced).weight(.bold)).tracking(1.4)
                            .foregroundStyle(on ? Theme.paper : Theme.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(on ? Theme.ink : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(Theme.ink.opacity(0.4), lineWidth: 0.7))
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Headphone steering")
                .accessibilityValue(on ? "On" : "Off")
                .accessibilityHint("Maps next and previous track to Higher and Lower, in the briefing only.")
                .accessibilityIdentifier("morningBriefing.remoteSteering")
            }
        }
    }
}
