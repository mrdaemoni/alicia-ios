import SwiftUI

/// What she is holding right now, and every day since she began.
///
/// Hector, 2026-09-18: *"Tapping on the Us title doesn't longer bring the
/// context Alicia has about me right now and also the timeline of since she
/// was born until today with a key happening per day. Next to the day and date
/// show the location."*
///
/// It was unmounted when the old orbit came out of Us, and the endpoints
/// (`/api/context_enrichment`, `/api/timeline`) kept working the whole time —
/// so this is a surface being put back, not a capability being invented.
///
/// Two halves, in the order he asked for them: the working picture she has of
/// him today, then the arc. The arc reaches past the data horizon to day one,
/// so most of it predates the phone ever reporting a place; those days simply
/// have no location, and none is inferred from a neighbouring day.
struct OurArcView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days: [TimelineDay] = []
    @State private var context: ContextEnrichment?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    whatSheHolds
                    arc
                }
                .padding(22)
            }
            .presenceBackground(.us, store: store)
            .foregroundStyle(Theme.ink)
            .buttonStyle(.plain)
            .toolbar(.hidden, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                InkTitleLine(text: "Us", size: 30)
                Text("EVERY DAY SINCE SHE BEGAN")
                    .font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button("CLOSE") { dismiss() }
                .font(.system(size: 10, design: .monospaced)).tracking(1)
                .frame(minHeight: 44)
                .accessibilityIdentifier("arc.close")
        }
    }

    /// Her working picture of him — the same items the enrichment surface
    /// edits, shown here read-only because this is "what does she think right
    /// now", not "change what she thinks".
    @ViewBuilder private var whatSheHolds: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT SHE'S HOLDING ABOUT YOU")
                .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                .foregroundStyle(Theme.inkSoft)
            if let context, !context.about.isEmpty {
                ForEach(context.about) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.subheadline)
                        Text(item.text).font(.system(size: 17, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("arc.about")
                }
                NavigationLink("Change what she's holding") { ContextEnrichmentView() }
                    .font(.callout).frame(minHeight: 44)
            } else if loading {
                Text("Reading her picture of you…").font(.subheadline).italic()
                    .foregroundStyle(Theme.inkSoft)
            } else {
                Text("She has nothing written down about you right now.")
                    .font(.system(size: 17, design: .serif)).italic()
            }
        }
    }

    private var arc: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE ARC")
                .font(.system(size: 10, design: .monospaced)).tracking(1.6)
                .foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 12)
            if days.isEmpty, loading {
                Text("Reading every day…").font(.subheadline).italic()
                    .foregroundStyle(Theme.inkSoft)
            } else if days.isEmpty {
                Text("The arc is unavailable. Nothing has been lost; connect to your Mac and pull to refresh.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(days) { day in
                dayRow(day)
            }
        }
    }

    private func dayRow(_ day: TimelineDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // The date and where he was, on one line — his ask exactly.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // A drawn mark, not a glyph: the app forbids emoji and SF
                // Symbols outright, and U+2733 renders as an emoji asterisk on
                // a real phone.
                if day.milestone {
                    InkSpark(size: 9, color: Theme.ink, seed: day.date.inkSeed)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                }
                Text(dayLabel(day.date))
                    .font(.system(size: 10, design: .monospaced)).tracking(1)
                    .foregroundStyle(Theme.inkSoft)
                if let place = day.place {
                    Text("· " + place.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .accessibilityIdentifier("arc.place")
                }
                Spacer(minLength: 0)
            }
            // One key happening. The headline is the day in a phrase; what
            // follows is the single most specific thing that actually occurred.
            Text(day.headline.strippedEmojis)
                .font(.system(size: day.milestone ? 20 : 18, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let keyMoment = keyMoment(day) {
                Text(keyMoment.strippedEmojis)
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 0.7) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("arc.day")
    }

    /// One line per day, chosen rather than concatenated: what she learned
    /// about him beats what the day circulated, which beats what happened.
    /// Three lists printed in full would make the arc unreadable.
    private func keyMoment(_ day: TimelineDay) -> String? {
        if let learned = day.learned?.first, !learned.isEmpty { return learned }
        if let thread = day.thread, !thread.isEmpty { return "Circling: " + thread }
        if let growth = day.growth.first, !growth.isEmpty { return growth }
        return day.what.first
    }

    private func dayLabel(_ date: String) -> String {
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        guard let parsed = iso.date(from: date) else { return date }
        let out = DateFormatter()
        out.dateFormat = "EEE d MMM yyyy"
        return out.string(from: parsed).uppercased()
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let arc = store.ourArc()
        async let picture = store.herPictureOfYou()
        days = await arc
        context = await picture
    }
}
