import SwiftUI
import WidgetKit
import AppIntents

enum RitualKind: String, AppEnum {
    case exercise, cold_plunge, sauna
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ritual"
    static var caseDisplayRepresentations: [RitualKind: DisplayRepresentation] = [
        .exercise: "Exercise", .cold_plunge: "Cold plunge", .sauna: "Sauna"]
}
struct LogRitualIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a ritual"
    static var description = IntentDescription("Save a completed ritual on this phone. Syncs to Alicia when the app opens.")
    @Parameter(title: "Ritual") var ritual: RitualKind
    init() {}
    init(_ ritual: RitualKind) { self.ritual = ritual }
    func perform() async throws -> some IntentResult {
        // Capture time belongs to this tap, not the potentially old timeline.
        var event = BodyEvent(kind: "ritual")
        event.source = "widget"; event.ritual = ritual.rawValue; event.completed = true
        try BodyCapture.save(event)
        WidgetCenter.shared.reloadTimelines(ofKind: "AliciaRituals")
        return .result()
    }
}
struct RitualEntry: TimelineEntry {
    let date: Date
    let events: [BodyEvent]
    let pending: Int
    let failed: Bool
}
struct RitualProvider: TimelineProvider {
    func placeholder(in context: Context) -> RitualEntry { .init(date: .now, events: [], pending: 0, failed: false) }
    func entry() -> RitualEntry {
        do { return try .init(date: .now, events: BodyCapture.events(), pending: BodyCapture.pending().count, failed: false) }
        catch { return .init(date: .now, events: [], pending: 0, failed: true) }
    }
    func getSnapshot(in context: Context, completion: @escaping (RitualEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RitualEntry>) -> Void) {
        let current = entry()
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(36 * 3600)
        let nextDay = Calendar.current.startOfDay(for: midnight)
        // Explicit midnight entry clears yesterday even if WidgetKit delays refresh.
        let tomorrow = RitualEntry(date: nextDay, events: current.events, pending: current.pending, failed: current.failed)
        completion(Timeline(entries: [current, tomorrow], policy: .after(nextDay)))
    }
}
struct RitualWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AliciaRituals", provider: RitualProvider()) { entry in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("BODY · DAILY RITUALS").font(.system(size: 10, design: .monospaced))
                    Spacer()
                    Text(entry.date, format: .dateTime.month(.abbreviated).day()).font(.caption)
                }
                HStack(spacing: 8) {
                    ForEach(RitualKind.allCases, id: \.self) { kind in
                        let done = BodyCapture.completed(kind.rawValue, at: entry.date, events: entry.events)
                        Button(intent: LogRitualIntent(kind)) {
                            VStack(spacing: 6) {
                                Text(BodyCapture.rituals.first { $0.0 == kind.rawValue }!.1)
                                Text(done ? "Recorded" : "Log it").font(.caption).italic()
                            }.frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(.plain)
                        .background(done ? Color.primary.opacity(0.08) : .clear)
                        .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 0.7))
                        .accessibilityLabel("Log completed " + kind.rawValue.replacingOccurrences(of: "_", with: " "))
                        .accessibilityValue(done ? "Recorded today" : "Not recorded")
                    }
                }
                Text(entry.failed ? "Open Alicia to check your local record." : entry.pending > 0 ? "Saved here · open Alicia to sync" : "Tap after each ritual · correct it in Body")
                    .font(.system(size: 10, design: .serif)).foregroundStyle(.secondary)
            }
            .font(.system(size: 14, design: .serif))
            .containerBackground(Color(red: 0.953, green: 0.933, blue: 0.890), for: .widget)
            .widgetURL(URL(string: "alicia://body"))
        }
        .configurationDisplayName("Daily rituals")
        .description("Exercise, cold plunge and sauna. One tap to record each; open Alicia to sync.")
        .supportedFamilies([.systemMedium])
    }
}
