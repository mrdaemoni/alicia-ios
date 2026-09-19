import SwiftUI

/// Us, Mind, Body, Alicia and Studio. Dialogue is a shared action.
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
    case knowledge = "Mind"
    case body = "Body"

    static let tabs: [AppSection] = [.us, .knowledge, .body, .mind, .studio]

    var id: String { rawValue }

#if DEBUG
    /// Lowercase name accepted by the `--tab` launch argument, so visual QA
    /// of a per-tab change is repeatable and scriptable.
    init?(launchName: String) {
        switch launchName.lowercased() {
        case "us":        self = .us
        case "dialogue":  self = .dialogue
        case "alicia": self = .mind
        case "body": self = .body
        case "studio":    self = .studio
        case "knowledge", "mind": self = .knowledge
        default:          return nil
        }
    }
#endif

    var symbol: String {
        switch self {
        case .us:      return "sun.horizon"
        case .dialogue: return "quote.bubble"
        case .mind:    return "hare"
        case .studio:  return "waveform"
        case .knowledge: return "books.vertical"
        case .body: return "body"
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var collaboration = store.collaboration
        // A hard layout, not a safe-area inset: the inset mechanism
        // repeatedly failed on device (bar floating above the bottom,
        // covering the composer). Content and bar are siblings — the bar
        // owns the bottom edge, period.
        VStack(spacing: 0) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ritual-widget-preview") {
                RitualWidgetContent(entry: RitualEntry(date: .now, events: [], pending: 0, failed: false),
                    forceAccented: ProcessInfo.processInfo.arguments.contains("--accented-preview"))
                    .frame(height: 160).padding(16)
            }
#endif
            if store.selectedSection == .dialogue {
                TalkView()
            } else {
            TabView(selection: $store.selectedSection) {
                ForEach(AppSection.tabs) { section in
                    tab(for: section)
                        .tag(section)
                        // The system bar is replaced by the editorial word-bar.
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            }
            // v28: the global PODCAST player was more clutter than comfort
            // (Hector: "then I have to close it") — it lives in Studio
            // again, and the lock screen / Dynamic Island covers the rest.
            // The reading bar is global on purpose and doesn't repeat that
            // mistake: it exists only while something is being read to you,
            // it follows you off the page you started it from, and its
            // crossed-out mark ends it in one tap.
            //
            // v39: the way to reach her is furniture, not a state. It used to
            // appear only when an episode existed, and both it and the tab bar
            // collapsed the moment the field took focus — so the one control
            // Hector reaches for most had three appearances and one of them
            // was nothing at all. Three permanent bands now, always in this
            // order: her, then what is being read to him, then where he is.
            ConversationComposer()
            ReadingBar()
            EditorialTabBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("alicia.openThoughtReturn"))) { _ in
            store.selectedSection = .mind
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("alicia.openCollaboration"))) { note in
            let info = note.userInfo ?? [:]
            store.collaboration.route = CollaborationRoute(candidateID: info["collaborationCandidate"] as? String ?? "",
                goalID: info["goalID"] as? String ?? "", connectionID: info["connectionID"] as? String ?? "",
                agreementID: info["agreementID"] as? String ?? "")
        }
        .task { store.collaboration.restoreRoute() }
        .sheet(item: $collaboration.route) { route in
            NavigationStack { CollaborationView(target: route) }
        }
        // Presence: which tab, for how long. Fires on every change including
        // the first, so the section he lands on is timed from the start.
        .task(id: store.selectedSection) {
            PresenceTracker.shared.section(store.selectedSection.rawValue)
        }
        // The dark band grows upward to take the player in, rather than a
        // card appearing on top of the page.
        .animation(.easeInOut(duration: 0.25), value: store.reader.isActive)
        // v30: a whisper-thin pill when the backend can't be reached or the
        // token died — otherwise a dead backend renders as an app that
        // merely "has nothing new", which is worse than an honest word.
        .overlay(alignment: .top) {
            ConnectionBanner()
                .padding(.top, 4)
        }
        // Serif body type everywhere — the sketchbook voice.
        .fontDesign(.serif)
        .fullScreenCover(isPresented: $store.showWalk) { WalkReflectionView() }
        // Writing to her is contextual: it belongs on top of the page he is
        // already on, carrying that page in with it, and it gives the page
        // back when he closes it. Dialogue stays a place he can also go.
        .sheet(isPresented: $store.showArc) {
            OurArcView().presentationDetents([.large])
        }
        .sheet(isPresented: $store.showConversation) {
            ConversationSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // The way back to a reflection, from wherever he happens to be.
        .sheet(item: $store.reviewRecording) { target in
            VoiceRecordingsView(recordingID: target.id)
        }
    }

    @ViewBuilder
    private func tab(for section: AppSection) -> some View {
        switch section {
        case .us:       HomeView()
        case .dialogue: TalkView()
        case .mind:     MindView()
        case .studio:   StudioView()
        case .knowledge: KnowledgeView()
        case .body: BodyView()
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
                // Still trying is not yet bad news: it reads as quiet, not as
                // an alarm, so a route change does not look like a failure.
                .foregroundStyle(ConnectionStatus.shared.state == .reaching ? Theme.inkSoft : Theme.rose)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.paper.opacity(0.92)))
                .overlay(Capsule().stroke((ConnectionStatus.shared.state == .reaching ? Theme.inkSoft : Theme.rose).opacity(0.35), lineWidth: 0.7))
        }
    }

    private func label(for state: ConnectionState) -> String? {
        switch state {
        case .ok:           return nil
        case .reaching:     return "reaching her…"
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
