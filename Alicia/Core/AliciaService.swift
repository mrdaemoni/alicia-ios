import Foundation

/// The single seam between the UI and Alicia's backend.
/// Swap `MockAliciaService` for a real URLSession-backed implementation and
/// the whole app is "networked" without touching any view.
protocol AliciaService {
    /// Streams a reply token-by-token, mirroring an LLM/SSE endpoint.
    func stream(_ prompt: String) -> AsyncStream<String>
    func thoughts() async -> [Thought]
    func tracks() async -> [Track]
    func gallery() async -> [Artwork]
    func health() async -> [HealthMetric]
    /// Ask Alicia to respond to a drawing you made.
    func complement(_ title: String) async -> Artwork
}

/// In-memory stand-in so the app runs with zero backend.
struct MockAliciaService: AliciaService {
    func stream(_ prompt: String) -> AsyncStream<String> {
        let reply = SampleData.reply(to: prompt)
        return AsyncStream { continuation in
            Task {
                for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(for: .milliseconds(45))
                    continuation.yield(String(word) + " ")
                }
                continuation.finish()
            }
        }
    }

    func thoughts() async -> [Thought] { SampleData.thoughts }
    func tracks() async -> [Track] { SampleData.tracks }
    func gallery() async -> [Artwork] { SampleData.gallery }
    func health() async -> [HealthMetric] { SampleData.health }

    func complement(_ title: String) async -> Artwork {
        try? await Task.sleep(for: .milliseconds(700))
        return Artwork(title: "Reply to \"\(title)\"",
                       note: "Alicia's response to your sketch",
                       symbol: "sparkle",
                       author: .alicia)
    }
}
