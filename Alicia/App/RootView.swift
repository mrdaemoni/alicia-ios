import SwiftUI

/// The five sections of Alicia. Health lives inside Us (status strip →
/// full vitals) so the tab bar stays at five and iOS never folds tabs
/// into a "More" item.
///
/// Names and icons follow the ink-on-paper identity: line-art symbols
/// (never filled) that echo the drawings — the sun over the sea from
/// `memories`, a spoken line, a single quiet spark, the waveform, the
/// contour scribble of the sketches themselves.
enum AppSection: String, CaseIterable, Identifiable {
    case us      = "Us"
    case dialogue = "Dialogue"
    case mind    = "Alicia"
    case studio  = "Studio"
    case knowledge = "Knowledge"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .us:      return "sun.horizon"
        case .dialogue: return "quote.bubble"
        case .mind:    return "hare"
        case .studio:  return "waveform"
        case .knowledge: return "books.vertical"
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        // A hard layout, not a safe-area inset: the inset mechanism
        // repeatedly failed on device (bar floating above the bottom,
        // covering the composer). Content and bar are siblings — the bar
        // owns the bottom edge, period.
        VStack(spacing: 0) {
            TabView(selection: $store.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    tab(for: section)
                        .tag(section)
                        // The system bar is replaced by the editorial word-bar.
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            // v27: the player travels with him — pause/scrub from any tab,
            // not just Studio. Hard sibling above the word-bar (the same
            // no-safeAreaInset doctrine as the bar itself); steps aside
            // when the Dialogue composer owns the bottom edge.
            if store.nowPlaying != nil, !store.composerFocused {
                PlayerBar()
            }
            EditorialTabBar()
        }
        .ignoresSafeArea(edges: .bottom)
        // Serif body type everywhere — the sketchbook voice.
        .fontDesign(.serif)
    }

    @ViewBuilder
    private func tab(for section: AppSection) -> some View {
        switch section {
        case .us:       HomeView()
        case .dialogue: TalkView()
        case .mind:     MindView()
        case .studio:   StudioView()
        case .knowledge: KnowledgeView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
