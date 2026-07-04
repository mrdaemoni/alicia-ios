import SwiftUI
import PencilKit

struct CanvasView: View {
    enum Mode: String, CaseIterable { case draw = "My Canvas", gallery = "Alicia's Gallery" }

    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .draw
    @State private var drawing = PKDrawing()
    @State private var toolsVisible = true

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
            .toolbar {
                if mode == .draw {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { toolsVisible.toggle() }
                        } label: {
                            Image(systemName: toolsVisible ? "pencil.slash" : "pencil.and.outline")
                        }
                        .accessibilityLabel(toolsVisible ? "Hide drawing tools" : "Show drawing tools")
                    }
                }
            }
        }
    }

    private var drawSurface: some View {
        VStack(spacing: 14) {
            PencilCanvas(drawing: $drawing, isActive: mode == .draw && toolsVisible)
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
                    // Ship the actual canvas so she sees what was drawn.
                    let png = drawing.bounds.isEmpty
                        ? nil
                        : drawing.image(from: drawing.bounds, scale: 2).pngData()
                    store.requestComplement(for: "Sketch", image: png)
                    mode = .gallery
                } label: {
                    Label("Ask Alicia to reply", systemImage: "hare.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Theme.accentGradient, in: Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            // The docked tool picker rises slightly above the tab bar; keep the
            // action buttons clear of it while the tools are up.
            .padding(.bottom, toolsVisible ? 32 : 8)
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
        .refreshable { await store.load() }
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
                    Group {
                        if let url = art.imageURL {
                            // Real render from the backend (Alicia's drawing)
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 32, weight: .light))
                                        .foregroundStyle(Theme.inkSoft)
                                default:
                                    ProgressView()
                                }
                            }
                        } else {
                            Image(systemName: art.symbol)
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(byAlicia ? .white : Theme.inkSoft)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(art.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 5) {
                Image(systemName: byAlicia ? "hare.fill" : "hand.draw")
                    .font(.caption2)
                Text(art.note).font(.caption2)
            }
            .foregroundStyle(byAlicia ? Theme.accentSoft : Theme.inkSoft)
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
