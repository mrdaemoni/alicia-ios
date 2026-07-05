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

    private var bar: some View {
        VStack(spacing: 0) {
            Theme.stroke.frame(height: 0.7)
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
                                             ? Theme.ink : Theme.inkSoft.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Theme.paper.opacity(0.97))
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
