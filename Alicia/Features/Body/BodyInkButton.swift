import SwiftUI

/// Body's text actions, in the app's own hand.
///
/// A bare SwiftUI `Button` draws its label in the inherited tint, and the app
/// tints from the root with `Theme.accent`. So every verb on this surface —
/// "Refresh Body", "Ask Alicia about my wellbeing", "Log it" — arrived as a
/// sea-slate link on bone paper. The accent is the one blue thread in Hector's
/// drawings, not the colour of every action.
///
/// Ink alone would leave "Log it" indistinguishable from "Exercise" beside it,
/// so the affordance is the one the navigation already uses: her hand-pulled
/// underline, in the word's own colour — dark on paper, light on an ink
/// ground, never a tint of its own. The style also restores the two states a
/// plain button loses, since an explicit foreground overrides the system's own
/// dimming.
struct InkAction: ButtonStyle {
    /// A stable name for this action's stroke, so the same button always
    /// wears the same line and nothing re-scribbles on scroll.
    var seed: String
    /// A secondary action — one that steps back from the reading rather than
    /// carrying it forward (discarding a rejected capture, paging evidence).
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, seed: seed, quiet: quiet)
    }

    private struct Face: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let seed: String
        let quiet: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(colour)
                .inkUnderlined(seed: seed, color: colour)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }

        private var colour: Color {
            // Still ink when it cannot be tapped, only faint — a disabled
            // action that vanishes reads as a missing one.
            guard isEnabled else { return Theme.inkSoft.opacity(0.45) }
            let base = quiet ? Theme.inkSoft : Theme.ink
            return configuration.isPressed ? base.opacity(0.5) : base
        }
    }
}

extension View {
    /// Ink over her underline, with press and disabled states.
    func inkAction(_ seed: String, quiet: Bool = false) -> some View {
        buttonStyle(InkAction(seed: seed, quiet: quiet))
    }
}
