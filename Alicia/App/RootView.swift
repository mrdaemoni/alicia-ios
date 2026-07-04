import SwiftUI

/// The five sections of Alicia. Health lives inside Home (status strip →
/// full vitals) so the tab bar stays at five and iOS never folds tabs
/// into a "More" item.
enum AppSection: String, CaseIterable, Identifiable {
    case home    = "Home"
    case talk    = "Talk"
    case mind    = "Alicia"
    case studio  = "Studio"
    case canvas  = "Canvas"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home:   return "house.fill"
        case .talk:   return "bubble.left.and.bubble.right.fill"
        case .mind:   return "sparkles"
        case .studio: return "waveform"
        case .canvas: return "paintbrush.pointed.fill"
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection = .home

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                tab(for: section)
                    .tag(section)
                    .tabItem { Label(section.rawValue, systemImage: section.symbol) }
            }
        }
    }

    @ViewBuilder
    private func tab(for section: AppSection) -> some View {
        switch section {
        case .home:   HomeView()
        case .talk:   TalkView()
        case .mind:   MindView()
        case .studio: StudioView()
        case .canvas: CanvasView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
