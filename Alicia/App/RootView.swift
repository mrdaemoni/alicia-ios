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
    case canvas  = "Canvas"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .us:      return "sun.horizon"
        case .dialogue: return "quote.bubble"
        case .mind:    return "hare"
        case .studio:  return "waveform"
        case .canvas:  return "scribble.variable"
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedSection) {
            ForEach(AppSection.allCases) { section in
                tab(for: section)
                    .tag(section)
                    .tabItem {
                        if section == .mind {
                            // Hector's own rabbit silhouette, template-tinted
                            // like the SF symbols around it.
                            Label { Text(section.rawValue) } icon: {
                                Image("TabRabbit").renderingMode(.template)
                            }
                        } else {
                            Label(section.rawValue, systemImage: section.symbol)
                        }
                    }
            }
        }
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
        case .canvas:   CanvasView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
