import SwiftUI

/// The Co-Star register, distilled: flat mono-caps navigation, serif
/// display headers, hairline rules. No rounded chrome.

/// Custom bottom bar — a hairline rule and five mono-caps words. Replaces
/// the system tab bar (hidden per-tab in RootView).
struct EditorialTabBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // v39: the bar no longer collapses. It used to fold to zero height
        // whenever the composer took focus, which is how Hector lost both the
        // navigation and the way to reach her at the same moment — the two
        // things most worth keeping on screen. Typing now happens in a sheet
        // above this bar (ConversationSheet), so there is nothing left to
        // make room for, and the bar simply owns the bottom edge always.
        bar
    }

    /// Bottom safe-area height (home indicator) — the ink swallows it.
    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    private var bar: some View {
        // v28: equal GAPS between natural-width words (equal columns made
        // the space after DIALOGUE huge and STUDIO·KNOWLEDGE cramped —
        // words this different in length need optical spacing).
        HStack(spacing: 0) {
            ForEach(Array(AppSection.tabs.enumerated()), id: \.element.id) { i, section in
                if i > 0 { Spacer(minLength: 8) }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.selectedSection = section
                    }
                } label: {
                    VStack(spacing: 2.5) {
                        Text(section.rawValue.uppercased())
                            .font(.system(size: 10, design: .monospaced)
                                .weight(store.selectedSection == section ? .bold : .regular))
                            .tracking(0.8)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(store.selectedSection == section
                                             ? Theme.paper : Theme.paper.opacity(0.55))
                        // Her mark under the chosen word — a hand-pulled
                        // line, not a pill or a tint.
                        InkUnderline(color: Theme.paper.opacity(0.9),
                                     seed: section.rawValue.inkSeed,
                                     lineWidth: 1.3)
                            .frame(width: 34, height: 5)
                            .opacity(store.selectedSection == section ? 1 : 0)
                    }
                    .padding(.top, 15)
                    .padding(.bottom, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        // The bar owns the true bottom edge now (RootView ignores the
        // bottom safe area) — pad the label row clear of the home
        // indicator and fill the whole band with ink.
        .padding(.bottom, bottomInset)
        .background(Theme.ink)
    }
}

/// The one section header: Studio's serif display type, top center, with a
/// small mono kicker underneath. Every tab opens with this.
struct SectionHeader: View {
    var title: String
    var kicker: String = ""

    var body: some View {
        VStack(spacing: 5) {
            // The section's name in her hand (v26) — leaning glyphs,
            // uneven baseline, hand-set.
            InkTitleLine(text: title, size: 30)
            if !kicker.isEmpty {
                Text(kicker.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }
}
