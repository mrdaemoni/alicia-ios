import SwiftUI
import WidgetKit
import AppIntents
import UIKit

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

/// Tinted widgets force white labels. A tiny full-color ink plate preserves contrast.
struct RitualWidgetContent: View {
    let entry: RitualEntry
    var forceAccented = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var accented: Bool { forceAccented || renderingMode == .accented }
    private var ink: Color { accented ? .white : Color(red: 0.12, green: 0.15, blue: 0.13) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BODY · DAILY RITUALS").font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
                Text(entry.date, format: .dateTime.month(.abbreviated).day()).font(.caption)
            }
            HStack(spacing: 8) {
                ForEach(RitualKind.allCases, id: \.self) { kind in
                    let done = BodyCapture.completed(kind.rawValue, at: entry.date, events: entry.events)
                    Button(intent: LogRitualIntent(kind)) {
                        VStack(spacing: 6) {
                            Text(BodyCapture.rituals.first { $0.0 == kind.rawValue }!.1).fontWeight(.semibold)
                            Text(done ? "Recorded" : "Log it").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(.plain)
                    .overlay(Rectangle().stroke(ink.opacity(0.55), lineWidth: 1))
                    .accessibilityLabel("Log completed " + kind.rawValue.replacingOccurrences(of: "_", with: " "))
                    .accessibilityValue(done ? "Recorded today" : "Not recorded")
                }
            }
            Text(entry.failed ? "Open Alicia to check your local record." : entry.pending > 0 ? "Saved here · open Alicia to sync" : "Tap after each ritual · correct it in Body")
                .font(.system(size: 11, design: .serif))
        }
        .font(.system(size: 14, design: .serif)).foregroundStyle(ink)
        .padding(accented ? 10 : 0)
        .background { if accented { contrastPlate } }
        .containerBackground(Color(red: 0.953, green: 0.933, blue: 0.890), for: .widget)
    }
    @ViewBuilder private var contrastPlate: some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: Self.plate).resizable().widgetAccentedRenderingMode(.fullColor)
                .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
        } else { Color(red: 0.08, green: 0.12, blue: 0.10) }
    }
    private static let plate: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor(red: 0.08, green: 0.12, blue: 0.10, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()
}
