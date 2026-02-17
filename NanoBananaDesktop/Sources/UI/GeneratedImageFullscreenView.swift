import AppKit
import SwiftUI

struct GeneratedImageFullscreenView: View {
    let image: NSImage
    let closeHint: String
    let onClose: () -> Void

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 8.0

    @State private var scale: CGFloat = 1.0
    @State private var accumulatedScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var scrollWheelMonitor: Any?
    @State private var middleMouseDownMonitor: Any?
    @State private var middleMouseDragMonitor: Any?
    @State private var middleMouseUpMonitor: Any?
    @State private var isMiddleMousePanning: Bool = false
    @State private var lastMiddleMouseLocation: CGPoint?

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(dragGesture)
                .simultaneousGesture(magnificationGesture)
                .onTapGesture {
                    onClose()
                }
                .padding(32)

            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        adjustScale(by: -0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button("100%") {
                        resetTransform()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        adjustScale(by: 0.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.bottom, 6)

                Text(closeHint)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            installScrollWheelMonitor()
            installMiddleMouseMonitors()
        }
        .onDisappear {
            removeScrollWheelMonitor()
            removeMiddleMouseMonitors()
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposedScale = accumulatedScale * value
                scale = min(max(minScale, proposedScale), maxScale)
            }
            .onEnded { _ in
                accumulatedScale = scale
                normalizeOffsetIfNeeded()
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else {
                    return
                }
                offset = CGSize(
                    width: accumulatedOffset.width + value.translation.width,
                    height: accumulatedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1.0 else {
                    resetOffset()
                    return
                }
                accumulatedOffset = offset
            }
    }

    private func adjustScale(by delta: CGFloat) {
        let nextScale = min(max(minScale, scale + delta), maxScale)
        scale = nextScale
        accumulatedScale = nextScale
        normalizeOffsetIfNeeded()
    }

    private func resetTransform() {
        scale = minScale
        accumulatedScale = minScale
        resetOffset()
    }

    private func normalizeOffsetIfNeeded() {
        if scale <= minScale {
            resetOffset()
        }
    }

    private func resetOffset() {
        offset = .zero
        accumulatedOffset = .zero
        isMiddleMousePanning = false
        lastMiddleMouseLocation = nil
    }

    private func installScrollWheelMonitor() {
        guard scrollWheelMonitor == nil else {
            return
        }

        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let delta = zoomDelta(for: event)
            guard delta != 0 else {
                return event
            }

            adjustScale(by: delta)
            return nil
        }
    }

    private func removeScrollWheelMonitor() {
        guard let scrollWheelMonitor else {
            return
        }
        NSEvent.removeMonitor(scrollWheelMonitor)
        self.scrollWheelMonitor = nil
    }

    private func installMiddleMouseMonitors() {
        guard middleMouseDownMonitor == nil,
              middleMouseDragMonitor == nil,
              middleMouseUpMonitor == nil else {
            return
        }

        middleMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber == 2, scale > minScale else {
                return event
            }

            isMiddleMousePanning = true
            lastMiddleMouseLocation = event.locationInWindow
            return nil
        }

        middleMouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { event in
            guard event.buttonNumber == 2, isMiddleMousePanning, scale > minScale else {
                return event
            }

            let currentLocation = event.locationInWindow
            if let lastMiddleMouseLocation {
                let deltaX = currentLocation.x - lastMiddleMouseLocation.x
                // NSEvent window coordinates use an inverted Y axis compared to SwiftUI DragGesture.
                // Invert Y delta so middle-click panning matches left-click drag behavior.
                let deltaY = -(currentLocation.y - lastMiddleMouseLocation.y)
                offset = CGSize(
                    width: offset.width + deltaX,
                    height: offset.height + deltaY
                )
                accumulatedOffset = offset
            }
            self.lastMiddleMouseLocation = currentLocation

            return nil
        }

        middleMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2 else {
                return event
            }

            if isMiddleMousePanning {
                isMiddleMousePanning = false
                lastMiddleMouseLocation = nil
                accumulatedOffset = offset
                return nil
            }

            return event
        }
    }

    private func removeMiddleMouseMonitors() {
        if let middleMouseDownMonitor {
            NSEvent.removeMonitor(middleMouseDownMonitor)
            self.middleMouseDownMonitor = nil
        }

        if let middleMouseDragMonitor {
            NSEvent.removeMonitor(middleMouseDragMonitor)
            self.middleMouseDragMonitor = nil
        }

        if let middleMouseUpMonitor {
            NSEvent.removeMonitor(middleMouseUpMonitor)
            self.middleMouseUpMonitor = nil
        }

        isMiddleMousePanning = false
        lastMiddleMouseLocation = nil
    }

    private func zoomDelta(for event: NSEvent) -> CGFloat {
        let rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        guard rawDelta != 0 else {
            return 0
        }

        let speedMultiplier: CGFloat = event.hasPreciseScrollingDeltas ? 0.015 : 0.08
        let normalizedMagnitude = max(0.04, min(abs(rawDelta) * speedMultiplier, 0.6))
        return rawDelta > 0 ? normalizedMagnitude : -normalizedMagnitude
    }
}
