import SwiftUI

/// The Co-Star register, distilled: flat mono-caps navigation, serif
/// display headers, hairline rules. No rounded chrome.

/// Custom bottom bar — a hairline rule and five mono-caps words. Replaces
/// the system tab bar (hidden per-tab in RootView).
struct EditorialTabBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // Collapse by height (not by removing the view) — swapping to
        // EmptyView glitched the safe-area inset and let the bar overlap
        // the Dialogue composer on device.
        bar
            .frame(height: store.composerFocused ? 0 : nil)
            .clipped()
            .opacity(store.composerFocused ? 0 : 1)
    }

    /// Bottom safe-area height (home indicator) — the ink swallows it.
    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { section in
                Button {
                    store.selectedSection = section
                } label: {
                    Text(section.rawValue.uppercased())
                        .font(.system(size: 10, design: .monospaced)
                            .weight(store.selectedSection == section ? .bold : .regular))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(store.selectedSection == section
                                         ? Theme.paper : Theme.paper.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        // Swallow the home-indicator zone into the ink: explicit bottom
        // padding sized to the window inset (ignoresSafeArea alone left a
        // paper slit under the bar during scroll).
        .padding(.bottom, bottomInset)
        .background(Theme.ink)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// The one section header: Studio's serif display type, top center, with a
/// small mono kicker underneath. Every tab opens with this.
struct SectionHeader: View {
    var title: String
    var kicker: String = ""

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
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
