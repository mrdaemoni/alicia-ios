import WidgetKit
import SwiftUI

/// Alicia on the home screen: her line of the moment and the synthesis of
/// the day, ink on bone. The app writes the shared cache (app group) on
/// every load; the widget just renders the freshest thing she said.
struct AliciaEntry: TimelineEntry {
    let date: Date
    let greeting: String
    let featuredTitle: String
    let note: String
}

struct AliciaProvider: TimelineProvider {
    static let suite = UserDefaults(suiteName: "group.com.myalicia.app")

    static func current() -> AliciaEntry {
        let d = suite
        return AliciaEntry(
            date: .now,
            greeting: d?.string(forKey: "widget.greeting")
                ?? "She's thinking of you.",
            featuredTitle: d?.string(forKey: "widget.featuredTitle")
                ?? "Open the app to let her speak.",
            note: d?.string(forKey: "widget.note") ?? "")
    }

    func placeholder(in context: Context) -> AliciaEntry { Self.current() }

    func getSnapshot(in context: Context, completion: @escaping (AliciaEntry) -> Void) {
        completion(Self.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AliciaEntry>) -> Void) {
        // Re-render hourly; the app refreshes the cache (and reloads the
        // timeline) whenever it loads, so this is just the heartbeat.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [Self.current()], policy: .after(next)))
    }
}

/// Ink on bone, matching Theme.swift (hardcoded — separate target).
private enum Ink {
    static let paper = Color(red: 0.953, green: 0.933, blue: 0.890)
    static let ink   = Color(red: 0.165, green: 0.153, blue: 0.137)
    static let soft  = Color(red: 0.42, green: 0.40, blue: 0.37)
    static let slate = Color(red: 0.282, green: 0.380, blue: 0.475)
}

struct AliciaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AliciaEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Ink.paper }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if let rabbit = UIImage(named: "rabbit") {
                        Image(uiImage: rabbit)
                            .resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(Ink.ink)
                    }
                    Text("ALICIA")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Ink.soft)
                }
                Spacer(minLength: 0)
                Text(entry.greeting)
                    .font(.system(size: 15, design: .serif).weight(.medium))
                    .foregroundStyle(Ink.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(5)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let rabbit = UIImage(named: "rabbit") {
                        Image(uiImage: rabbit)
                            .resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(Ink.ink)
                    }
                    Text("ALICIA")
                        .font(.system(size: 9, design: .monospaced).weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(Ink.soft)
                    Spacer()
                    Text(entry.date, style: .date)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Ink.soft)
                }
                Text(entry.greeting)
                    .font(.system(size: 16, design: .serif).weight(.semibold))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Rectangle().fill(Ink.ink.opacity(0.15)).frame(height: 0.7)
                Text("TODAY'S SYNTHESIS")
                    .font(.system(size: 8, design: .monospaced).weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Ink.slate)
                Text(entry.featuredTitle)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(Ink.ink.opacity(0.85))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AliciaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AliciaWidget", provider: AliciaProvider()) {
            AliciaWidgetView(entry: $0)
        }
        .configurationDisplayName("Alicia")
        .description("Her line of the moment and the synthesis of the day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct AliciaWidgets: WidgetBundle {
    var body: some Widget {
        AliciaWidget()
    }
}
