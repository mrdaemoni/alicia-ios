import SwiftUI

/// Ink on paper.
///
/// The design language comes from Hector's own drawings (~/alicia art):
/// hand-pulled topographic contour lines in warm ink on bone paper — a lone
/// figure before the sea, spirals of attention, a face emerging from the
/// grain. So the app is a sketchbook, not a dashboard: warm paper ground,
/// near-black warm ink, one restrained sea-slate accent (the blue thread
/// that appears in the spiral drawings), hairline ink borders, serif type.
enum Theme {
    // Paper & ink
    static let paper    = Color(red: 0.953, green: 0.933, blue: 0.890)  // bone
    static let paperDeep = Color(red: 0.914, green: 0.886, blue: 0.831) // shadowed paper
    static let ink      = Color(red: 0.165, green: 0.153, blue: 0.137)  // warm near-black
    /// Secondary text: dark warm gray — pencil, not silver. System
    /// `.secondary` reads washed-out against the paper.
    // Secondary text/controls: the same near-black as the ink, only quieter
    // through opacity — the warm gray didn't fit the engraving register.
    static let inkSoft  = Color(red: 0.165, green: 0.153, blue: 0.137).opacity(0.78)

    // The one accent: sea-slate, from the blue thread in the spiral pieces.
    static let accent     = Color(red: 0.282, green: 0.380, blue: 0.475)
    static let accentSoft = Color(red: 0.408, green: 0.514, blue: 0.608)

    // Muted ink-wash tones (kept under the old names so call sites hold)
    static let mint  = Color(red: 0.420, green: 0.490, blue: 0.373)  // sage
    static let amber = Color(red: 0.690, green: 0.541, blue: 0.310)  // ochre
    static let rose  = Color(red: 0.651, green: 0.357, blue: 0.294)  // seal red

    // Cards are breaths of lighter paper — transparent enough that the
    // drawing underneath stays part of the page. No frames: the page is one
    // continuous piece, not mounted swatches.
    static let card   = Color.white.opacity(0.22)
    static let stroke = ink.opacity(0.14)

    static var backdrop: LinearGradient {
        LinearGradient(colors: [paper, paperDeep],
                       startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Paper-card look: a breath of lighter paper, frameless.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// One of Hector's drawings living behind a page.
///
/// `full` lays the drawing across the whole page at low opacity (Dialogue,
/// Studio); otherwise it washes into the top and fades out like a print
/// soaking through (Us, Alicia). `drift` makes the page breathe — an
/// imperceptibly slow scale-and-rise loop, one inhale per minute.
struct ArtBackgroundModifier: ViewModifier {
    let imageName: String
    var opacity: Double = 0.38
    var full: Bool = false
    var drift: Bool = false
    @State private var breathing = false

    func body(content: Content) -> some View {
        content.background(
            ZStack(alignment: .top) {
                Theme.backdrop
                if full {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .opacity(opacity)
                        .scaleEffect(breathing ? 1.05 : 1.0)
                        .ignoresSafeArea()
                } else {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .opacity(opacity)
                        .frame(maxHeight: 460, alignment: .top)
                        .clipped()
                        .mask(
                            LinearGradient(
                                stops: [.init(color: .black, location: 0),
                                        .init(color: .black.opacity(0.65), location: 0.55),
                                        .init(color: .clear, location: 1)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .scaleEffect(breathing ? 1.06 : 1.0, anchor: .top)
                        .offset(y: breathing ? -10 : 0)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                }
                Spacer()
            }
            .ignoresSafeArea()
        )
        .onAppear {
            guard drift else { return }
            withAnimation(.easeInOut(duration: 52).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// Full-bleed paper background for a section.
    func sectionBackground() -> some View {
        background(Theme.backdrop.ignoresSafeArea())
    }

    func artBackground(_ imageName: String, opacity: Double = 0.38,
                       full: Bool = false, drift: Bool = false) -> some View {
        modifier(ArtBackgroundModifier(imageName: imageName, opacity: opacity,
                                       full: full, drift: drift))
    }
}
