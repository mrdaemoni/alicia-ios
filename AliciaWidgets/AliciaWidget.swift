import WidgetKit
import SwiftUI

/// Alicia on the home screen (v27): her line in her own hand, what's in
/// your ears, and what she's asking you to carry — on paper that follows
/// the hour (rose at dawn, bone by day, ochre at dusk, ink at night).
/// The app writes the shared cache (app group) on every load; the widget
/// renders the freshest layer of it and re-tints itself hourly.
struct AliciaEntry: TimelineEntry {
    let date: Date
    let greeting: String
    let featuredTitle: String
    let note: String
    let todayLabel: String
    let todayTitle: String
    let context: String
    let carry: String
}

struct AliciaProvider: TimelineProvider {
    static let suite = UserDefaults(suiteName: "group.com.myalicia.app")

    static func entry(at date: Date) -> AliciaEntry {
        let d = suite
        return AliciaEntry(
            date: date,
            greeting: d?.string(forKey: "widget.greeting")
                ?? "She's thinking of you.",
            featuredTitle: d?.string(forKey: "widget.featuredTitle")
                ?? "Open the app to let her speak.",
            note: d?.string(forKey: "widget.note") ?? "",
            todayLabel: d?.string(forKey: "widget.todayLabel") ?? "",
            todayTitle: d?.string(forKey: "widget.todayTitle") ?? "",
            context: d?.string(forKey: "widget.context") ?? "",
            carry: d?.string(forKey: "widget.carry") ?? "")
    }

    func placeholder(in context: Context) -> AliciaEntry { Self.entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (AliciaEntry) -> Void) {
        completion(Self.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AliciaEntry>) -> Void) {
        // One entry per hour boundary so the paper follows the light even
        // when the app hasn't opened; the app reloads timelines on load.
        let cal = Calendar.current
        var entries: [AliciaEntry] = [Self.entry(at: .now)]
        for h in 1...8 {
            if let d = cal.date(byAdding: .hour, value: h, to: cal.date(
                bySetting: .minute, value: 0, of: .now) ?? .now) {
                entries.append(Self.entry(at: d))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Ink on paper, following the hour (hardcoded — separate target).
private struct Hour {
    let paper: Color
    let ink: Color
    let soft: Color
    let slate: Color

    static func at(_ date: Date) -> Hour {
        let bone  = Color(red: 0.953, green: 0.933, blue: 0.890)
        let ink   = Color(red: 0.165, green: 0.153, blue: 0.137)
        let slate = Color(red: 0.282, green: 0.380, blue: 0.475)
        switch Calendar.current.component(.hour, from: date) {
        case 5..<9:    // dawn — rose washes the bone
            return Hour(paper: Color(red: 0.955, green: 0.905, blue: 0.870),
                        ink: ink, soft: ink.opacity(0.68), slate: slate)
        case 9..<17:   // day — plain bone
            return Hour(paper: bone,
                        ink: ink, soft: ink.opacity(0.66), slate: slate)
        case 17..<21:  // dusk — ochre leans in
            return Hour(paper: Color(red: 0.945, green: 0.905, blue: 0.820),
                        ink: ink, soft: ink.opacity(0.68), slate: slate)
        default:       // night — she writes in bone on ink
            return Hour(paper: Color(red: 0.135, green: 0.140, blue: 0.170),
                        ink: bone, soft: bone.opacity(0.62),
                        slate: Color(red: 0.560, green: 0.660, blue: 0.760))
        }
    }
}

struct AliciaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AliciaEntry

    private var hour: Hour { Hour.at(entry.date) }

    var body: some View {
        content
            .containerBackground(for: .widget) { hour.paper }
    }

    private var kickerRow: some View {
        HStack(spacing: 4) {
            if let rabbit = UIImage(named: "rabbit") {
                Image(uiImage: rabbit)
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(hour.ink)
            }
            Text("ALICIA")
                .font(.system(size: 8, design: .monospaced).weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(hour.soft)
            Spacer()
            if family != .systemSmall {
                Text(entry.date, style: .date)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(hour.soft)
            }
        }
    }

    private func hairline() -> some View {
        Rectangle().fill(hour.ink.opacity(0.16)).frame(height: 0.7)
    }

    private var script: Font {
        // Zapfino — the same scribbling pen the app writes with (v28).
        .custom("Zapfino", size: family == .systemLarge ? 16 : 14)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                kickerRow
                Spacer(minLength: 0)
                Text(entry.greeting)
                    .font(.custom("Zapfino", size: 12))
                    .foregroundStyle(hour.ink)
                    .minimumScaleFactor(0.65)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .systemLarge:
            VStack(alignment: .leading, spacing: 9) {
                kickerRow
                Text(entry.greeting)
                    .font(script)
                    .foregroundStyle(hour.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                hairline()
                if !entry.todayTitle.isEmpty {
                    Text("IN YOUR EARS · \(entry.todayLabel)")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(hour.slate)
                    Text(entry.todayTitle)
                        .font(.system(size: 16, design: .serif).weight(.semibold))
                        .foregroundStyle(hour.ink)
                        .lineLimit(2)
                }
                if !entry.carry.isEmpty {
                    Text("TO CARRY")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(hour.slate)
                    Text(entry.carry)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(hour.ink.opacity(0.85))
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                hairline()
                Text(entry.featuredTitle)
                    .font(.system(size: 12, design: .serif))
                    .italic()
                    .foregroundStyle(hour.soft)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:  // systemMedium
            VStack(alignment: .leading, spacing: 7) {
                kickerRow
                Text(entry.greeting)
                    .font(script)
                    .foregroundStyle(hour.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                hairline()
                if !entry.todayTitle.isEmpty {
                    Text("IN YOUR EARS · \(entry.todayLabel)")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(hour.slate)
                    Text(entry.todayTitle)
                        .font(.system(size: 13, design: .serif).weight(.semibold))
                        .foregroundStyle(hour.ink)
                        .lineLimit(1)
                } else {
                    Text(entry.featuredTitle)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(hour.ink.opacity(0.85))
                        .lineLimit(2)
                }
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
        .description("Her hand, what's in your ears, and what to carry today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AliciaWidgets: WidgetBundle {
    var body: some Widget {
        AliciaWidget()
    }
}
