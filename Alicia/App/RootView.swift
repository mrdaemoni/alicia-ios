import SwiftUI

/// The five sections of Alicia.
enum AppSection: String, CaseIterable, Identifiable {
    case talk    = "Talk"
    case mind    = "Alicia"
    case studio  = "Studio"
    case canvas  = "Canvas"
    case health  = "Health"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .talk:   return "bubble.left.and.bubble.right.fill"
        case .mind:   return "sparkles"
        case .studio: return "waveform"
        case .canvas: return "paintbrush.pointed.fill"
        case .health: return "waveform.path.ecg"
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection = .talk

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
        case .talk:   TalkView()
        case .mind:   MindView()
        case .studio: StudioView()
        case .canvas: CanvasView()
        case .health: HealthView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
