import SwiftUI

struct EpisodeReadAlongButton: View {
    @Environment(AppStore.self) private var store
    let track: Track
    @State private var preparing = false
    @State private var error: String?
    @State private var showReader = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(preparing ? "Preparing the reading…" : error != nil ? "Retry read along" : "Read along with this episode") {
                preparing = true; error = nil
            }.disabled(preparing).frame(minHeight: 44)
            if preparing { Text("The episode can keep playing while its text is prepared.").font(.caption) }
            if let error { Text(error).font(.caption).foregroundStyle(Theme.inkSoft) }
        }
        .sheet(isPresented: $showReader) { ImmersiveReadingView() }
        .task(id: preparing) {
            guard preparing else { return }
            for attempt in 0..<180 {
                let result = await store.prepareEpisodeReading(track, prepare: attempt == 0)
                guard !Task.isCancelled else { return }
                switch result {
                case .ready(let chunks, let duration):
                    store.readAlongWithEpisode(track, chunks: chunks, duration: duration)
                    preparing = false; showReader = true; return
                case .rendering, .streaming:
                    try? await Task.sleep(for: .seconds(3))
                case .failed, .unavailable:
                    error = "The episode text is unavailable. You can keep listening and retry later."
                    preparing = false; return
                }
            }
            error = "The text is still preparing on the Mac. Try again shortly."
            preparing = false
        }
    }
}
