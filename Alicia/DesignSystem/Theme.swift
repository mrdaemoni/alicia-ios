import SwiftUI

/// Central palette + reusable styling so every section feels like one app.
enum Theme {
    static let accent     = Color(red: 0.55, green: 0.45, blue: 0.95)
    static let accentSoft = Color(red: 0.72, green: 0.58, blue: 0.99)
    static let mint       = Color(red: 0.35, green: 0.85, blue: 0.72)
    static let amber      = Color(red: 0.98, green: 0.72, blue: 0.35)
    static let rose       = Color(red: 0.97, green: 0.45, blue: 0.60)

    static let card   = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.09)

    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.09, green: 0.07, blue: 0.17),
                     Color(red: 0.03, green: 0.03, blue: 0.07)],
            startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Frosted rounded-card look used across sections.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// Full-bleed themed background for a section.
    func sectionBackground() -> some View {
        background(Theme.backdrop.ignoresSafeArea())
    }
}
