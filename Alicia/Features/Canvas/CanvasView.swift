import SwiftUI
import PencilKit

struct CanvasView: View {
    enum Mode: String, CaseIterable { case draw = "My Canvas", gallery = "Alicia's Gallery" }

    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .draw
    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(16)

                switch mode {
                case .draw:    drawSurface
                case .gallery: gallery
                }
            }
            .sectionBackground()
            .navigationTitle("Canvas")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var drawSurface: some View {
        VStack(spacing: 14) {
            PencilCanvas(drawing: $drawing, isActive: mode == .draw)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    drawing = PKDrawing()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: Capsule())
                }
                Button {
                    store.requestComplement(for: "Sketch")
                    mode = .gallery
                } label: {
                    Label("Ask Alicia to reply", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Theme.accentGradient, in: Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(store.gallery) { ArtworkCell(art: $0) }
            }
            .padding(16)
        }
    }
}

struct ArtworkCell: View {
    let art: Artwork
    private var byAlicia: Bool { art.author == .alicia }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(byAlicia ? AnyShapeStyle(Theme.accentGradient)
                               : AnyShapeStyle(Color.white.opacity(0.08)))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: art.symbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(byAlicia ? .white : .secondary)
                )
            Text(art.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 5) {
                Image(systemName: byAlicia ? "sparkles" : "hand.draw")
                    .font(.caption2)
                Text(art.note).font(.caption2)
            }
            .foregroundStyle(byAlicia ? Theme.accentSoft : .secondary)
            .lineLimit(1)
        }
        .card(padding: 10, radius: 20)
    }
}

#Preview {
    CanvasView()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
