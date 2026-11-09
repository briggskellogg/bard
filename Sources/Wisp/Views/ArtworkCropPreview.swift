import SwiftUI
import WispCore

/// Shows the same integer crop rectangle used by the final encoder, without
/// recompressing an image on every mouse movement.
struct ArtworkCropPreview: View {
    let source: ArtworkCropSource
    @Binding var selection: ArtworkCropSelection
    let side: CGFloat
    @GestureState private var drag = CGSize.zero
    @FocusState private var focused: Bool

    private var visibleSelection: ArtworkCropSelection {
        selection.panned(dx: drag.width, dy: drag.height, viewportSide: side,
                         sourceWidth: source.pixelWidth, sourceHeight: source.pixelHeight)
    }

    var body: some View {
        ZStack {
            if let image = source.image.cropping(to: visibleSelection.pixelRect(
                sourceWidth: source.pixelWidth, sourceHeight: source.pixelHeight)) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            }
            if drag != .zero {
                Path { path in
                    for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                        path.move(to: CGPoint(x: side * fraction, y: 0))
                        path.addLine(to: CGPoint(x: side * fraction, y: side))
                        path.move(to: CGPoint(x: 0, y: side * fraction))
                        path.addLine(to: CGPoint(x: side, y: side * fraction))
                    }
                }.stroke(.white.opacity(0.45), lineWidth: 0.5).allowsHitTesting(false)
            }
        }
        .frame(width: side, height: side).contentShape(Rectangle()).clipped()
        .focusable().focused($focused)
        .onTapGesture { focused = true }
        .gesture(DragGesture(minimumDistance: 1)
            .updating($drag) { value, state, _ in state = value.translation }
            .onChanged { _ in focused = true }
            .onEnded { value in pan(value.translation.width, value.translation.height) })
        .onMoveCommand { direction in
            switch direction {
            case .left: pan(-5, 0)
            case .right: pan(5, 0)
            case .up: pan(0, -5)
            case .down: pan(0, 5)
            @unknown default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Square cover crop")
        .accessibilityHint("Drag to reposition. Use arrow keys to fine-tune and the zoom slider to resize.")
        .accessibilityAction(named: "Move left") { pan(-5, 0) }
        .accessibilityAction(named: "Move right") { pan(5, 0) }
        .accessibilityAction(named: "Move up") { pan(0, -5) }
        .accessibilityAction(named: "Move down") { pan(0, 5) }
    }

    private func pan(_ dx: CGFloat, _ dy: CGFloat) {
        selection = selection.panned(dx: dx, dy: dy, viewportSide: side,
                                    sourceWidth: source.pixelWidth, sourceHeight: source.pixelHeight)
    }
}
