import SwiftUI
import PencilKit

/// The shared drawing room — mounted inside Studio ("draw with me").
struct CanvasBody: View {
    enum Mode: String, CaseIterable { case draw = "My Canvas", gallery = "Alicia's Gallery" }

    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .draw
    @State private var drawing = PKDrawing()
    @State private var toolsVisible = true
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 8)

            switch mode {
            case .draw:    drawSurface
            case .gallery: gallery
            }
        }
    }

    private var drawSurface: some View {
        VStack(spacing: 14) {
            // The shared sheet: her overlay strokes live UNDER the live
            // PencilKit layer, so Hector always draws on top of her last
            // move — and she on top of his. GeometryReader gives the true
            // canvas size for compositing.
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(store.canvasOverlays.enumerated()), id: \.offset) { _, layer in
                        Image(uiImage: layer)
                            .resizable()
                            .scaledToFill()
                    }
                    PencilCanvas(drawing: $drawing, isActive: mode == .draw && toolsVisible)
                }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, new in canvasSize = new }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
            .padding(.horizontal, 16)

            if let caption = store.cocreateCaption {
                Text("🐇 \(caption)")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .transition(.opacity)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    drawing = PKDrawing()
                    store.clearCanvasCocreation()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: Capsule())
                }
                Button {
                    Task {
                        await store.aliciaContinues(
                            composite: compositeImage(), canvasSize: canvasSize,
                            anchor: lastPenPoint())
                    }
                } label: {
                    if store.isCocreating {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("she's drawing…")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Theme.accentGradient, in: Capsule())
                    } else {
                        Label("Alicia continues", systemImage: "hare.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                }
                .disabled(store.isCocreating)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            // The docked tool picker rises slightly above the tab bar; keep the
            // action buttons clear of it while the tools are up.
            .padding(.bottom, toolsVisible ? 32 : 8)
        }
    }

    /// Where the pencil stopped: the last point of the last stroke,
    /// normalized to the canvas — her strokes begin there.
    private func lastPenPoint() -> CGPoint? {
        guard let stroke = drawing.strokes.last,
              canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let path = stroke.path
        guard !path.isEmpty else { return nil }
        let p = path[path.count - 1].location
        return CGPoint(x: min(1, max(0, p.x / canvasSize.width)),
                       y: min(1, max(0, p.y / canvasSize.height)))
    }

    /// Flatten paper + her overlays + his live strokes into one image —
    /// what she "sees" when deciding where to draw next.
    private func compositeImage() -> UIImage {
        let size = canvasSize == .zero ? CGSize(width: 390, height: 500) : canvasSize
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(Theme.paper).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for layer in store.canvasOverlays {
                layer.draw(in: CGRect(origin: .zero, size: size))
            }
            let img = drawing.image(from: CGRect(origin: .zero, size: size), scale: 1)
            img.draw(in: CGRect(origin: .zero, size: size))
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
    CanvasBody()
        .environment(AppStore(service: MockAliciaService()))
        .tint(Theme.accent)
}
