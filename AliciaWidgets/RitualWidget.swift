import SwiftUI
import WidgetKit
import AppIntents

struct RitualProvider: TimelineProvider {
    func placeholder(in context: Context) -> RitualEntry { .init(date: .now, events: [], pending: 0, failed: false) }
    func entry() -> RitualEntry {
        do {
            let pending = try BodyCapture.pending()
            return try .init(date: .now, events: BodyCapture.events(), pending: pending.count,
                             failed: false, pendingIDs: Set(pending.map(\.id)))
        }
        catch { return .init(date: .now, events: [], pending: 0, failed: true) }
    }
    func getSnapshot(in context: Context, completion: @escaping (RitualEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RitualEntry>) -> Void) {
        let current = entry()
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(36 * 3600)
        let nextDay = Calendar.current.startOfDay(for: midnight)
        // Explicit midnight entry clears yesterday even if WidgetKit delays refresh.
        let tomorrow = RitualEntry(date: nextDay, events: current.events, pending: current.pending,
                                   failed: current.failed, pendingIDs: current.pendingIDs)
        completion(Timeline(entries: [current, tomorrow], policy: .after(nextDay)))
    }
}
struct RitualWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AliciaRituals", provider: RitualProvider()) { entry in
            RitualWidgetContent(entry: entry)
            .widgetURL(URL(string: "alicia://body"))
        }
        .configurationDisplayName("Daily rituals")
        .description("Exercise, cold plunge and sauna. One tap to record each; open Alicia to sync.")
        .supportedFamilies([.systemMedium])
    }
}
