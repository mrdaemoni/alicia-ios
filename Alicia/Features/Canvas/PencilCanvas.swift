import SwiftUI
import PencilKit

/// SwiftUI wrapper around PKCanvasView with the system tool picker.
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput          // finger or Apple Pencil
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator

        let picker = context.coordinator.toolPicker
        picker.addObserver(canvas)
        picker.setVisible(isActive, forFirstResponder: canvas)
        if isActive {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if canvas.drawing != drawing { canvas.drawing = drawing }

        let picker = context.coordinator.toolPicker
        picker.setVisible(isActive, forFirstResponder: canvas)
        if isActive {
            // Defer outside the SwiftUI update pass, matching makeUIView — a
            // synchronous becomeFirstResponder here skips the keyboard
            // safe-area update, leaving content under the re-shown picker.
            if !canvas.isFirstResponder {
                DispatchQueue.main.async { canvas.becomeFirstResponder() }
            }
        } else if canvas.isFirstResponder {
            canvas.resignFirstResponder()
        }
    }

    // The tool picker outlives the canvas (it belongs to the coordinator), so it
    // must be hidden explicitly when the canvas leaves the hierarchy — otherwise
    // it stays docked over the tab bar in gallery mode.
    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        let toolPicker = PKToolPicker()
        init(_ parent: PencilCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
