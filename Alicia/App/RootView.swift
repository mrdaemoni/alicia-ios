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
            // v28: the global player was more clutter than comfort
            // (Hector: "then I have to close it") — it lives in Studio
            // again, and the lock screen / Dynamic Island covers the rest.
            EditorialTabBar()
        }
        .ignoresSafeArea(edges: .bottom)
        // v30: a whisper-thin pill when the backend can't be reached or the
        // token died — otherwise a dead backend renders as an app that
        // merely "has nothing new", which is worse than an honest word.
        .overlay(alignment: .top) {
            ConnectionBanner()
                .padding(.top, 4)
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
        case .knowledge: KnowledgeView()
        }
    }
}

/// Small connection-state pill (top of every tab). Reads the shared
/// `ConnectionStatus` the live fetch layer writes; in mock mode the state
/// never leaves `.ok`, so nothing renders. Deliberately unobtrusive — a
/// margin note, not an alert.
private struct ConnectionBanner: View {
    var body: some View {
        if let text = label(for: ConnectionStatus.shared.state) {
            Text(text)
                .font(.system(size: 11, design: .serif).italic())
                .foregroundStyle(Theme.rose)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.paper.opacity(0.92)))
                .overlay(Capsule().stroke(Theme.rose.opacity(0.35), lineWidth: 0.7))
        }
    }

    private func label(for state: ConnectionState) -> String? {
        switch state {
        case .ok:           return nil
        case .unreachable:  return "she's unreachable right now"
        case .unauthorized: return "token rejected — check Secrets.plist"
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
