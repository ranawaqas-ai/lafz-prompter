import SwiftUI

/// Strips along the prompter's bottom and side edges: drag them to change its
/// height and width. The top stays under the notch, and the window keeps its
/// alignment, so a centred prompter grows on both sides at once.
struct PrompterResizeHandles: View {
    @ObservedObject var viewModel: PrompterViewModel

    /// Same limits as the Width and Height sliders in Settings.
    static let widthRange: ClosedRange<CGFloat> = 150...600
    static let heightRange: ClosedRange<CGFloat> = 80...500
    private static let thickness: CGFloat = 8

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                handle(.bottom).frame(height: Self.thickness)
            }
            HStack {
                // A left-aligned prompter is pinned at its left edge, a
                // right-aligned one at its right, so only the free side drags.
                if viewModel.horizontalAlignment != .left {
                    handle(.left).frame(width: Self.thickness)
                }
                Spacer()
                if viewModel.horizontalAlignment != .right {
                    handle(.right).frame(width: Self.thickness)
                }
            }
        }
    }

    private enum Edge { case bottom, left, right }

    private func handle(_ edge: Edge) -> some View {
        ResizeStrip(cursor: edge == .bottom ? .resizeUpDown : .resizeLeftRight) { start, mouse in
            switch edge {
            case .bottom:
                // Screen y grows upward, so dragging down is a negative change.
                let height = start.height + (start.mouse.y - mouse.y)
                viewModel.prompterHeight = height.clamped(to: Self.heightRange).rounded()
            case .left, .right:
                let dx = edge == .right ? mouse.x - start.mouse.x : start.mouse.x - mouse.x
                // Centred: the opposite edge moves too, so the width changes twice as much.
                let factor: CGFloat = viewModel.horizontalAlignment == .center ? 2 : 1
                let width = start.width + dx * factor
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
