import SwiftUI

/// Alicia's vitals — a calm dashboard of how she's running.
/// Lives inside Home's NavigationStack (pushed from the status strip), so
/// it deliberately has no NavigationStack of its own.
struct HealthView: View {
    @Environment(AppStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusBanner
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.health) { MetricTile(metric: $0) }
                }
            }
            .padding(16)
        }
        .refreshable { await store.load() }
        .sectionBackground()
        .navigationTitle("Health")
    }

    private var statusBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.mint.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.mint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("All systems nominal").font(.headline)
                Text("Last check just now").font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .card(padding: 16)
    }
}

struct MetricTile: View {
    let metric: HealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: metric.symbol)
                    .foregroundStyle(metric.color)
                Spacer()
                Text(metric.display)
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            Gauge(value: metric.value) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(metric.color)
            Text(metric.name)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }
}

#Preview {
    HealthView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
