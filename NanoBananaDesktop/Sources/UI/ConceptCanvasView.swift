import AppKit
import SwiftUI

struct ConceptCanvasView: View {
    @ObservedObject var viewModel: ConceptingViewModel
    let emptyTitle: String
    let emptyDescription: String

    @State private var currentStroke: [CGPoint] = []
    @State private var hoverLocation: CGPoint?
    @State private var pendingFillPoint: CGPoint?
    private let canvasCornerRadius: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let fittedSize = aspectFitSize(for: viewModel.canvasSize, in: geometry.size)
            let scaledSize = CGSize(
                width: fittedSize.width * viewModel.zoomScale,
                height: fittedSize.height * viewModel.zoomScale
            )

            ScrollView([.horizontal, .vertical]) {
                drawingSurface(size: scaledSize)
                .padding(40)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .scrollIndicators(.automatic)
        }
    }

    @ViewBuilder
    private func drawingSurface(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.08))

            if let image = viewModel.canvasCompositeImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous))
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))

                    Text(emptyTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(emptyDescription)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            if !currentStroke.isEmpty {
                currentStrokePath
                    .stroke(
                        previewStrokeColor,
                        style: StrokeStyle(
                            lineWidth: displayBrushDiameter(for: size),
                            lineCap: .round,
                            lineJoin: .round,
                            dash: viewModel.activeTool == .eraser ? [8, 6] : []
                        )
                    )
            }

            if let hoverLocation, showsBrushPreview {
                Circle()
                    .stroke(
                        viewModel.activeTool == .eraser
                            ? Color.white.opacity(0.82)
                            : viewModel.brushColor.swiftUIColor.opacity(0.9),
                        lineWidth: 1.5
                    )
                    .background(
                        Circle()
                            .fill(
                                viewModel.activeTool == .eraser
                                    ? Color.white.opacity(0.08)
                                    : viewModel.brushColor.swiftUIColor.opacity(0.12)
                            )
                    )
                    .frame(
                        width: max(displayBrushDiameter(for: size), 8),
                        height: max(displayBrushDiameter(for: size), 8)
                    )
                    .position(hoverLocation)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous))
        .gesture(drawingGesture(canvasSize: size))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = clampedPoint(location, size: size)
            case .ended:
                hoverLocation = nil
            }
        }
    }

    private var showsBrushPreview: Bool {
        viewModel.activeTool == .brush || viewModel.activeTool == .eraser
    }

    private var previewStrokeColor: Color {
        if viewModel.activeTool == .eraser {
            return Color.white.opacity(0.88)
        }
        return viewModel.brushColor.swiftUIColor.opacity(viewModel.brushOpacity)
    }

    private func drawingGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard viewModel.canDrawOnSelectedLayer else { return }
                let point = clampedPoint(value.location, size: canvasSize)
                hoverLocation = point
                if viewModel.activeTool == .fill {
                    pendingFillPoint = point
                    return
                }
                if currentStroke.isEmpty {
                    currentStroke = [point]
                } else if currentStroke.last != point {
                    currentStroke.append(point)
                }
            }
            .onEnded { _ in
                guard viewModel.canDrawOnSelectedLayer else {
                    currentStroke.removeAll()
                    return
                }
                let normalized = currentStroke.map { point in
                    ConceptPoint(
                        x: max(0, min(1, point.x / max(canvasSize.width, 1))),
                        y: max(0, min(1, point.y / max(canvasSize.height, 1)))
                    )
                }
                let fillPoint = pendingFillPoint.map { point in
                    ConceptPoint(
                        x: max(0, min(1, point.x / max(canvasSize.width, 1))),
                        y: max(0, min(1, point.y / max(canvasSize.height, 1)))
                    )
                }
                currentStroke.removeAll()
                pendingFillPoint = nil
                if viewModel.activeTool == .fill, let fillPoint {
                    viewModel.fill(at: fillPoint)
                    return
                }
                guard normalized.count >= 2 else { return }
                viewModel.commitStroke(points: normalized)
            }
    }

    private var currentStrokePath: Path {
        Path { path in
            guard let first = currentStroke.first else { return }
            path.move(to: first)
            for point in currentStroke.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func clampedPoint(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    private func aspectFitSize(for canvasSize: CGSize, in availableSize: CGSize) -> CGSize {
        let maxWidth = max(availableSize.width - 96, 200)
        let maxHeight = max(availableSize.height - 96, 200)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        let scale = min(maxWidth / canvasSize.width, maxHeight / canvasSize.height)
        return CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
    }

    private func displayBrushDiameter(for size: CGSize) -> CGFloat {
        let baseWidth = max(viewModel.canvasSize.width, 1)
        let displayScale = size.width / baseWidth
        return max(CGFloat(viewModel.brushWidth) * displayScale, 1)
    }
}

extension ConceptRGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
