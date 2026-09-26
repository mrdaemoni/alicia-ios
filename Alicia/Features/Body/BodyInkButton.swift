import SwiftUI

/// Body's old text-action style, now a thin alias onto the app's one grammar
/// (DesignSystem/InkUI.swift, docs/INK_UI.md).
///
/// It used to draw every verb as ink over her hand-pulled underline — the same
/// cue Body's navigation links wore, so "Log it" and "View history" read as
/// the same kind of thing. Actions are now mono capitals; navigation is a
/// serif line with her chevron. Anything still calling `.inkAction(_:)`
/// (MindBodyOverview) gets the quiet action, so the file keeps compiling and
/// the look stays coherent while call sites move to the InkUI styles.
struct InkAction: ButtonStyle {
    /// Kept for source compatibility; the quiet style draws its own stroke.
    var seed: String
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        InkButtonStyle(role: .quiet).makeBody(configuration: configuration)
    }
}

extension View {
    /// Deprecated: use `.buttonStyle(.inkQuiet)` (or another InkUI style).
    func inkAction(_ seed: String, quiet: Bool = false) -> some View {
        buttonStyle(InkAction(seed: seed, quiet: quiet))
    }
}
