import SwiftUI

/// Body's text actions, in the app's own hand.
///
/// A bare SwiftUI `Button` draws its label in the inherited tint, and the app
/// tints from the root with `Theme.accent`. So every verb on this surface —
/// "Refresh Body", "Ask Alicia about my wellbeing", "Log it" — arrived as a
/// sea-slate link on bone paper. The accent is the one blue thread in Hector's
/// drawings, not the colour of every action. Every other surface already says
/// this with `.buttonStyle(.plain)` over an explicit `Theme.ink` foreground;
/// this is that same idiom, with the two states a plain button otherwise
/// loses — pressed and disabled — put back, since an explicit foreground also
/// overrides the system's own dimming.
struct InkAction: ButtonStyle {
    /// A secondary action — one that steps back from the reading rather than
    /// carrying it forward (discarding a rejected capture, paging evidence).
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, quiet: quiet)
    }

    private struct Face: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let quiet: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(colour)
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
    /// `.buttonStyle(.plain)` over `Theme.ink`, with press and disabled states.
    func inkAction(quiet: Bool = false) -> some View {
        buttonStyle(InkAction(quiet: quiet))
    }
}
