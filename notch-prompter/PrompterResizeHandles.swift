import SwiftUI

/// Strips along the prompter's bottom and side edges, and its bottom corners:
/// drag them to change the height, the width, or both. The top stays under
/// the notch, and the window keeps its alignment, so a centred prompter grows
/// on both sides at once.
struct PrompterResizeHandles: View {
    @ObservedObject var viewModel: PrompterViewModel

    /// Same limits as the Width and Height sliders in Settings.
    static let widthRange: ClosedRange<CGFloat> = 150...600
    static let heightRange: ClosedRange<CGFloat> = 80...500
    private static let edge: CGFloat = 12
    private static let corner: CGFloat = 24
    @State private var hovering = false

    var body: some View {
        // A left-aligned prompter is pinned at its left edge and a right-aligned
        // one at its right, so only the free side has handles.
        let left = viewModel.horizontalAlignment != .left
        let right = viewModel.horizontalAlignment != .right
        ZStack {
            ResizeGrips(left: left, right: right, color: viewModel.prompterTheme.textColor)
                .opacity(hovering ? 0.7 : 0.25)
                .animation(.easeInOut(duration: 0.15), value: hovering)
                .allowsHitTesting(false)
            VStack {
                Spacer()
                handle(.bottom).frame(height: Self.edge)
            }
            HStack {
                if left { handle(.left).frame(width: Self.edge) }
                Spacer()
                if right { handle(.right).frame(width: Self.edge) }
            }
            // Corners last, so they sit above the edges where they overlap.
            VStack {
                Spacer()
                HStack {
                    if left { handle(.bottomLeft).frame(width: Self.corner, height: Self.corner) }
                    Spacer()
                    if right { handle(.bottomRight).frame(width: Self.corner, height: Self.corner) }
                }
            }
        }
        .onHover { hovering = $0 }
    }

    private func handle(_ position: NSCursor.FrameResizePosition) -> some View {
        let horizontal: CGFloat = [.left, .bottomLeft].contains(position) ? -1
            : [.right, .bottomRight].contains(position) ? 1 : 0
        let vertical = [.bottom, .bottomLeft, .bottomRight].contains(position)
        return ResizeStrip(cursor: .frameResize(position: position, directions: .all)) { start, mouse in
            if vertical {
                // Screen y grows upward, so dragging down is a negative change.
                let height = start.height + (start.mouse.y - mouse.y)
                viewModel.prompterHeight = height.clamped(to: Self.heightRange).rounded()
            }
            if horizontal != 0 {
                // Centred: the opposite edge moves too, so the width changes twice as much.
                let factor: CGFloat = viewModel.horizontalAlignment == .center ? 2 : 1
                let width = start.width + (mouse.x - start.mouse.x) * horizontal * factor
                viewModel.prompterWidth = width.clamped(to: Self.widthRange).rounded()
            }
        } began: {
            viewModel.isResizing = true
            return (viewModel.prompterWidth, viewModel.prompterHeight)
        } ended: {
            viewModel.isResizing = false
        }
    }
}

/// Visible hints for the handles: a bar centred on each draggable edge and an
/// L-shaped mark in each draggable corner. Faint until the pointer is over the
/// prompter.
private struct ResizeGrips: View {
    let left: Bool
    let right: Bool
    let color: Color

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                Capsule().fill(color).frame(width: 36, height: 4).padding(.bottom, 3)
            }
            HStack {
                if left { Capsule().fill(color).frame(width: 4, height: 28).padding(.leading, 3) }
                Spacer()
                if right { Capsule().fill(color).frame(width: 4, height: 28).padding(.trailing, 3) }
            }
            VStack {
                Spacer()
                HStack {
                    if left { CornerMark().stroke(color, style: Self.stroke).scaleEffect(x: -1).frame(width: 10, height: 10) }
                    Spacer()
                    if right { CornerMark().stroke(color, style: Self.stroke).frame(width: 10, height: 10) }
                }
                .padding(5)
            }
        }
    }

    private static let stroke = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
}

/// The bottom-right corner of a frame: a line down the right side and along
/// the bottom.
private struct CornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// An invisible strip with a resize cursor that reports the pointer's screen
/// position while dragged. Screen coordinates, because the window itself
/// moves and grows under the pointer during the drag.
///
/// AppKit rather than a SwiftUI gesture: the prompter is a non-activating
/// panel that is never key, so a click on it is a "first mouse" click that
/// SwiftUI drops, and only an active app's hover can change the cursor.
private struct ResizeStrip: NSViewRepresentable {
    typealias Start = (width: CGFloat, height: CGFloat, mouse: CGPoint)

    let cursor: NSCursor
    let changed: (Start, CGPoint) -> Void
    let began: () -> (CGFloat, CGFloat)
    let ended: () -> Void

    init(cursor: NSCursor,
         changed: @escaping (Start, CGPoint) -> Void,
         began: @escaping () -> (CGFloat, CGFloat),
         ended: @escaping () -> Void) {
        self.cursor = cursor
        self.changed = changed
        self.began = began
        self.ended = ended
    }

    func makeNSView(context: Context) -> ResizeStripView { ResizeStripView() }

    func updateNSView(_ view: ResizeStripView, context: Context) {
        view.cursor = cursor
        view.changed = changed
        view.began = began
        view.ended = ended
    }
}

private final class ResizeStripView: NSView {
    var cursor: NSCursor = .arrow
    var changed: ((ResizeStrip.Start, CGPoint) -> Void)?
    var began: (() -> (CGFloat, CGFloat))?
    var ended: (() -> Void)?
    private var start: ResizeStrip.Start?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) {
        if start == nil { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let (width, height) = began?() else { return }
        start = (width, height, NSEvent.mouseLocation)
        cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        changed?(start, NSEvent.mouseLocation)
        cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        ended?()
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
