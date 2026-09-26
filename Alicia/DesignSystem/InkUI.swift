import SwiftUI

// MARK: - The grammar
//
// Hector, 2026-09-26: "To know if a link takes you somewhere, a button performs
// some action … and the containment around information — which information
// belongs to another one." Before this file every screen invented its own:
// six looks for Close, five for Listen, seven for refresh, and links and
// actions that were the same accent mono word. One rule now, everywhere:
//
//   GOES SOMEWHERE   a serif sentence ending in her chevron ›        InkLinkLabel + .inkLink
//   DOES SOMETHING   a word in mono capitals                          .inkPrimary / .inkSecondary / .inkQuiet
//   REMOVES          the same, in seal red                            .inkDestructive
//   OPENS HERE       a quiet sentence with a chevron that turns down  InkDisclosure
//   CHOOSES          a chip, filled when chosen                       WorkReviewChoice / InkTabs
//
// Containment: a section is a hairline, a kicker, and everything under it
// until the next hairline (InkSection). Things that belong to ONE item — a
// goal and its work, a recording and its state — sit inside one card (.card).
// Nothing interactive is ever plain body text, and nothing plain is ever
// drawn like a control.

enum InkType {
    /// Section kickers: small mono capitals, wide tracking, soft ink.
    static let kicker = Font.system(size: 10, design: .monospaced)
    static let kickerTracking: CGFloat = 2
    /// Every action label.
    static let action = Font.system(size: 11, design: .monospaced).weight(.semibold)
    static let actionTracking: CGFloat = 1.4
    /// A navigation row's title, and its smaller inline form.
    static let link = Font.system(size: 17, design: .serif)
    static let linkSmall = Font.system(size: 15, design: .serif)
    /// A subsection or item title inside a section.
    static let subhead = Font.system(size: 21, design: .serif)
    static let body = Font.system(size: 16, design: .serif)
    /// Dates, counts, provenance.
    static let meta = Font.caption
}

// MARK: Sections

/// The one hairline, used between sections and between items of a list.
struct InkRule: View {
    var opacity: Double = 1
    var body: some View {
        Rectangle().fill(Theme.stroke.opacity(opacity)).frame(height: 0.7)
            .accessibilityHidden(true)
    }
}

/// A section kicker on its own: mono capitals in soft ink.
struct InkKicker: View {
    var text: String
    var color: Color = Theme.inkSoft
    var body: some View {
        Text(text.uppercased())
            .font(InkType.kicker).tracking(InkType.kickerTracking)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section: a hairline, the kicker (with an optional trailing control on the
/// same line), and the content it owns. The rule makes the ownership visible:
/// everything below belongs to this kicker until the next rule.
struct InkSection<Trailing: View, Content: View>: View {
    var kicker: String
    var rule = true
    var spacing: CGFloat = 12
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if rule { InkRule().padding(.bottom, 6) }
            HStack(alignment: .firstTextBaseline) {
                InkKicker(text: kicker)
                Spacer(minLength: 12)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension InkSection where Trailing == EmptyView {
    init(kicker: String, rule: Bool = true, spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.init(kicker: kicker, rule: rule, spacing: spacing, trailing: { EmptyView() }, content: content)
    }
}

// MARK: Navigation — goes somewhere

/// The label of anything that takes him somewhere: a serif title, an optional
/// line of detail, and her chevron at the trailing edge. Use it inside a
/// NavigationLink or a Button that routes, with `.buttonStyle(.inkLink)`.
struct InkLinkLabel: View {
    var title: String
    var detail: String = ""
    var small = false
    /// Leaves the app (a web page): the share-arrow instead of the chevron.
    var external = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.strippedEmojis)
                    .font(small ? InkType.linkSmall : InkType.link)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if !detail.isEmpty {
                    Text(detail.strippedEmojis).font(InkType.meta).foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            if external {
                InkShareGlyph(size: small ? 14 : 16, color: Theme.inkSoft, seed: title.inkSeed)
            } else {
                InkChevron(pointing: .right, size: small ? 12 : 14, color: Theme.inkSoft, seed: title.inkSeed)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The press state for navigation rows. The label carries the look.
struct InkLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: Actions — does something

/// Every action: its words in mono capitals. `role` sets the weight:
/// primary (filled ink, one per screen or section — the thing this place is
/// for), secondary (outlined), quiet (underlined — refresh, retry, fold), and
/// destructive (seal red, outlined — delete, let go, clear).
struct InkButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, quiet, destructive }
    var role: Role
    /// Primary and secondary fill the width by default; quiet hugs its words.
    var fullWidth: Bool? = nil

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, role: role, fullWidth: fullWidth ?? (role == .primary))
    }

    private struct Face: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let role: Role
        let fullWidth: Bool

        var body: some View {
            let label = configuration.label
                .textCase(.uppercase)
                .font(role == .quiet ? InkType.kicker.weight(.semibold) : InkType.action)
                .tracking(role == .quiet ? 1.6 : InkType.actionTracking)
                .multilineTextAlignment(.center)
            switch role {
            case .primary:
                label
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
                    .background(Theme.ink.opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.75 : 1),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            case .secondary, .destructive:
                let tint = role == .destructive ? Theme.rose : Theme.ink
                label
                    .foregroundStyle(tint.opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.55 : 1))
                    .padding(.horizontal, 16)
                    .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(isEnabled ? 0.45 : 0.2), lineWidth: 1))
                    .contentShape(Rectangle())
            case .quiet:
                let colour = !isEnabled ? Theme.inkSoft.opacity(0.45)
                    : configuration.isPressed ? Theme.ink.opacity(0.5) : Theme.ink
                label
                    .foregroundStyle(colour)
                    .inkUnderlined(seed: "quiet", color: colour.opacity(0.7))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var inkPrimary: InkButtonStyle { InkButtonStyle(role: .primary) }
    static var inkSecondary: InkButtonStyle { InkButtonStyle(role: .secondary) }
    static var inkQuiet: InkButtonStyle { InkButtonStyle(role: .quiet) }
    static var inkDestructive: InkButtonStyle { InkButtonStyle(role: .destructive) }
    /// Secondary that hugs its words, for a row of two or three actions.
    static var inkSecondaryCompact: InkButtonStyle { InkButtonStyle(role: .secondary, fullWidth: false) }
    static var inkDestructiveCompact: InkButtonStyle { InkButtonStyle(role: .destructive, fullWidth: false) }
}

extension ButtonStyle where Self == InkLinkStyle {
    static var inkLink: InkLinkStyle { InkLinkStyle() }
}

// MARK: Disclosure — opens here

/// Replaces DisclosureGroup (whose chevron is a system glyph). A quiet serif
/// line with her chevron pointing down; it turns up while open. The content
/// is indented under a thin rule so it reads as belonging to the line.
struct InkDisclosure<Content: View>: View {
    var title: String
    @State private var open: Bool
    @ViewBuilder var content: () -> Content

    init(_ title: String, initiallyOpen: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._open = State(initialValue: initiallyOpen)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InkDisclosureToggle(title: title, open: open) { open.toggle() }
            if open {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Theme.stroke).frame(width: 0.7)
                    VStack(alignment: .leading, spacing: 10) { content() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
    }
}

/// The header line of a disclosure, for an owner that holds the open state
/// itself (it may also open from elsewhere, or reset on save).
struct InkDisclosureToggle: View {
    let title: String
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { action() } } label: {
            HStack(spacing: 8) {
                Text(title.strippedEmojis).font(InkType.linkSmall).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
                InkChevron(pointing: open ? .up : .down, size: 11, color: Theme.inkSoft, seed: title.inkSeed)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Open" : "Closed")
    }
}

// MARK: Notices

/// Status that is not a control. Errors are always seal red, with her spark;
/// information is soft italic; a confirmation is ink.
struct InkNotice: View {
    enum Kind { case error, info, success }
    var text: String
    var kind: Kind = .info
    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if kind == .error { InkSpark(size: 10, color: Theme.rose, seed: 7) }
                Text(text.strippedEmojis)
                    .font(kind == .info ? .callout.italic() : .callout)
                    .foregroundStyle(kind == .error ? Theme.rose : kind == .info ? Theme.inkSoft : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Page chrome

/// "CLOSE" for a sheet's toolbar: the same word everywhere a sheet ends.
struct InkCloseButton: View {
    var action: (() -> Void)? = nil
    var identifier: String = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { if let action { action() } else { dismiss() } } label: {
            Text("CLOSE").font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1.6)
                .foregroundStyle(Theme.ink).fixedSize()
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier(identifier.isEmpty ? "ink.close" : identifier)
    }
}

extension View {
    /// A page pushed inside a stack: her BACK, her title in the middle, no
    /// system chevron.
    func inkPushedPage(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { InkBackButton() }
                ToolbarItem(placement: .principal) { InkTitleLine(text: title, size: 16) }
            }
    }

    /// The root of a sheet: her title in the middle and CLOSE at the trailing
    /// edge. Pass `close` when closing means more than dismissing.
    func inkSheetPage(_ title: String, closeIdentifier: String = "", close: (() -> Void)? = nil) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { InkTitleLine(text: title, size: 16) }
                ToolbarItem(placement: .topBarTrailing) { InkCloseButton(action: close, identifier: closeIdentifier) }
            }
    }
}

// MARK: Inputs

extension View {
    /// Every place he writes: one field shape — lighter paper, a hairline,
    /// the same rounding as the actions.
    func inkField(minHeight: CGFloat? = nil) -> some View {
        self
            .font(InkType.body)
            .padding(12)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(Theme.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke, lineWidth: 0.7))
    }
}
