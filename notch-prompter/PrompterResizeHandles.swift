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
    private static let edge: CGFloat = 8
    private static let corner: CGFloat = 16

    var body: some View {
        // A left-aligned prompter is pinned at its left edge and a right-aligned
        // one at its right, so only the free side has handles.
        let left = viewModel.horizontalAlignment != .left
        let right = viewModel.horizontalAlignment != .right
        ZStack {
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

/// An invisible strip with a resize cursor that reports the pointer's screen
/// position while dragged. Screen coordinates, because the window itself
/// moves and grows under the pointer during the drag.
private struct ResizeStrip: View {
    typealias Start = (width: CGFloat, height: CGFloat, mouse: CGPoint)

    let cursor: NSCursor
    let changed: (Start, CGPoint) -> Void
    let began: () -> (CGFloat, CGFloat)
    let ended: () -> Void
    @State private var start: Start?

    init(cursor: NSCursor,
         changed: @escaping (Start, CGPoint) -> Void,
         began: @escaping () -> (CGFloat, CGFloat),
         ended: @escaping () -> Void) {
        self.cursor = cursor
        self.changed = changed
        self.began = began
        self.ended = ended
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { cursor.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        let mouse = NSEvent.mouseLocation
                        if start == nil {
                            let (width, height) = began()
                            start = (width, height, mouse)
                        }
                        if let start { changed(start, mouse) }
                    }
                    .onEnded { _ in
                        start = nil
                        ended()
                    }
            )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
