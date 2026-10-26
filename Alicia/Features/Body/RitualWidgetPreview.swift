#if DEBUG
import SwiftUI

/// The home-screen widget, on screen, in both rendering modes.
///
/// `RitualWidgetContent` lives in `Shared/`, so the app target compiles it and
/// can show it without adding the widget to a simulator home screen. Only the
/// pair is worth looking at: her underline takes the word's own colour, so it
/// must come out dark on bone paper and light on the tinted plate.
struct RitualWidgetPreview: View {
    private var entry: RitualEntry {
        var logged = BodyEvent(kind: "ritual")
        logged.source = "widget"; logged.ritual = "exercise"; logged.completed = true
        return RitualEntry(date: .now, events: [logged], pending: 1, failed: false,
                           pendingIDs: [logged.id])
    }
    var body: some View {
        VStack(spacing: 22) {
            Text("WIDGET · ON PAPER").font(.system(size: 10, design: .monospaced)).tracking(2)
            RitualWidgetContent(entry: entry)
                .frame(height: 160)
                .padding(14).background(InkPalette.paper)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityIdentifier("widget.plain")
            Text("WIDGET · TINTED").font(.system(size: 10, design: .monospaced)).tracking(2)
            RitualWidgetContent(entry: entry, forceAccented: true)
                .frame(height: 160)
                .padding(14).background(Color(red: 0.08, green: 0.12, blue: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityIdentifier("widget.accented")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backdrop.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }
}
#endif
