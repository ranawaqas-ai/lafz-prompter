import SwiftUI

/// Handles on the prompter's bottom and side edges and its bottom corners:
/// drag them to change the height, the width, or both. The top stays under
/// the notch, and the window keeps its alignment, so a centred prompter grows
/// on both sides at once.
///
/// Feedback follows the macOS conventions for resizable frames: the resize
/// pointer over a handle, the handle's grip lit in the accent colour on hover
/// and while dragging, and the size shown live during the drag.
struct PrompterResizeHandles: View {
    @Bindable var viewModel: PrompterViewModel
    @State private var pointerInside = false
    @State private var hovered: Handle?
    @State private var dragging: Handle?

    private static let edge: CGFloat = 24
    private static let corner: CGFloat = 48

    enum Handle: CaseIterable {
        case bottom, left, right, bottomLeft, bottomRight

        var cursorPosition: NSCursor.FrameResizePosition {
            switch self {
            case .bottom: return .bottom
            case .left: return .left
            case .right: return .right
            case .bottomLeft: return .bottomLeft
            case .bottomRight: return .bottomRight
            }
        }
        var horizontal: CGFloat {
            switch self {
            case .left, .bottomLeft: return -1
            case .right, .bottomRight: return 1
            case .bottom: return 0
            }
        }
        var vertical: Bool { [.bottom, .bottomLeft, .bottomRight].contains(self) }
    }

    var body: some View {
        // A left-aligned prompter is pinned at its left edge and a right-aligned
        // one at its right, so only the free side has handles.
        let left = viewModel.horizontalAlignment != .left
        let right = viewModel.horizontalAlignment != .right
        ZStack {
            ResizeGrips(left: left, right: right,
                        color: viewModel.prompterTheme.textColor,
                        pointerInside: pointerInside,
                        active: dragging ?? hovered)
                .allowsHitTesting(false)

            if dragging != nil {
                Text("\(Int(viewModel.prompterWidth)) × \(Int(viewModel.prompterHeight))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Edges stop where the corners start: overlapping areas would leave
            // the pointer inside an edge while it is over a corner, so moving
            // from the corner along the edge would never re-enter the edge.
            VStack {
                Spacer()
                handle(.bottom).frame(height: Self.edge)
                    .padding(.horizontal, Self.corner)
            }
            HStack {
                if left { handle(.left).frame(width: Self.edge) }
                Spacer()
                if right { handle(.right).frame(width: Self.edge) }
            }
            .padding(.bottom, Self.corner)
            VStack {
                Spacer()
                HStack {
                    if left { handle(.bottomLeft).frame(width: Self.corner, height: Self.corner) }
                    Spacer()
                    if right { handle(.bottomRight).frame(width: Self.corner, height: Self.corner) }
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: dragging)
        .animation(.easeInOut(duration: 0.15), value: pointerInside)
        .onHover { pointerInside = $0 }
    }

    private func handle(_ handle: Handle) -> some View {
        ResizeStrip(cursor: .frameResize(position: handle.cursorPosition, directions: .all)) { start, mouse in
            if handle.vertical {
                // Screen y grows upward, so dragging down is a negative change.
                let height = start.height + (start.mouse.y - mouse.y)
                viewModel.prompterHeight = height.clamped(to: viewModel.prompterHeightRange).rounded()
            }
            if handle.horizontal != 0 {
                // Centred: the opposite edge moves too, so the width changes twice as much.
                let factor: CGFloat = viewModel.horizontalAlignment == .center ? 2 : 1
                let width = start.width + (mouse.x - start.mouse.x) * handle.horizontal * factor
                viewModel.prompterWidth = width.clamped(to: viewModel.prompterWidthRange).rounded()
            }
        } began: {
            viewModel.isResizing = true
            dragging = handle
            return (viewModel.prompterWidth, viewModel.prompterHeight)
        } ended: {
            viewModel.isResizing = false
            dragging = nil
        } hoverChanged: { inside in
            if inside { hovered = handle } else if hovered == handle { hovered = nil }
        }
    }
}

/// The visible grips: a bar centred on each draggable edge and an L in each
/// draggable corner. Faint at rest, clearer with the pointer over the
/// prompter, and the active one in the accent colour.
private struct ResizeGrips: View {
    let left: Bool
    let right: Bool
    let color: Color
    let pointerInside: Bool
    let active: PrompterResizeHandles.Handle?

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                grip(.bottom) { Capsule().frame(width: 64, height: 6) }
                    .padding(.bottom, 5)
            }
            HStack {
                if left { grip(.left) { Capsule().frame(width: 6, height: 48) }.padding(.leading, 5) }
                Spacer()
                if right { grip(.right) { Capsule().frame(width: 6, height: 48) }.padding(.trailing, 5) }
            }
            VStack {
                Spacer()
                HStack {
                    if left {
                        grip(.bottomLeft) { CornerMark().stroke(style: Self.stroke).scaleEffect(x: -1) }
                            .frame(width: 20, height: 20)
                    }
                    Spacer()
                    if right {
                        grip(.bottomRight) { CornerMark().stroke(style: Self.stroke) }
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(7)
            }
        }
    }

    private static let stroke = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)

    private func grip<S: View>(_ handle: PrompterResizeHandles.Handle, @ViewBuilder _ shape: () -> S) -> some View {
        let isActive = active == handle
        return shape()
            .foregroundStyle(isActive ? Color.accentColor : color)
            .opacity(isActive ? 1 : pointerInside ? 0.55 : 0.2)
            .scaleEffect(isActive ? 1.2 : 1)
            .shadow(color: .black.opacity(isActive ? 0.4 : 0), radius: 3)
    }
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

/// An invisible handle that shows a resize pointer, reports hover, and
/// reports the pointer's screen position while dragged. Screen coordinates,
/// because the window itself moves and grows under the pointer.
///
/// AppKit rather than a SwiftUI gesture: the prompter is a non-activating
/// panel that is never key, so a click on it is a "first mouse" click that
/// SwiftUI drops.
private struct ResizeStrip: NSViewRepresentable {
    typealias Start = (width: CGFloat, height: CGFloat, mouse: CGPoint)

    let cursor: NSCursor
    let changed: (Start, CGPoint) -> Void
    let began: () -> (CGFloat, CGFloat)
    let ended: () -> Void
    let hoverChanged: (Bool) -> Void

    init(cursor: NSCursor,
         changed: @escaping (Start, CGPoint) -> Void,
         began: @escaping () -> (CGFloat, CGFloat),
         ended: @escaping () -> Void,
         hoverChanged: @escaping (Bool) -> Void) {
        self.cursor = cursor
        self.changed = changed
        self.began = began
        self.ended = ended
        self.hoverChanged = hoverChanged
    }

    func makeNSView(context: Context) -> ResizeStripView {
        // Before any hover: a pointer set in the same event that turns the
        // switch on is still ignored.
        BackgroundCursor.enable()
        return ResizeStripView()
    }

    func updateNSView(_ view: ResizeStripView, context: Context) {
        view.cursor = cursor
        view.changed = changed
        view.began = began
        view.ended = ended
        view.hoverChanged = hoverChanged
    }
}

private final class ResizeStripView: NSView {
    var cursor: NSCursor = .arrow
    var changed: ((ResizeStrip.Start, CGPoint) -> Void)?
    var began: (() -> (CGFloat, CGFloat))?
    var ended: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    private var start: ResizeStrip.Start?
    private var inside = false
    /// The handle that set the pointer last. Moving straight from one handle
    /// to the next can deliver the old one's exit after the new one's enter,
    /// so only this handle may reset the pointer to the arrow.
    private static weak var pointerOwner: ResizeStripView?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }

    // The window resets the pointer as it moves; setting it on every move
    // over the handle keeps the resize pointer showing.
    override func mouseMoved(with event: NSEvent) { cursor.set() }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        Self.pointerOwner = self
        cursor.set()
        hoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        inside = false
        hoverChanged?(false)
        resetPointerIfOwner()
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
        if !inside { resetPointerIfOwner() }
    }

    private func resetPointerIfOwner() {
        guard start == nil, Self.pointerOwner === self else { return }
        Self.pointerOwner = nil
        NSCursor.arrow.set()
    }
}

/// macOS ignores pointer changes from an app that is not active, and the
/// prompter deliberately never activates the app. The window server has a
/// per-connection switch for this, used by other always-on-top utilities;
/// it is not public API, so it is looked up at run time and skipped if it
/// is missing. Without it the grips still light up, only the pointer stays
/// an arrow.
private enum BackgroundCursor {
    private static var enabled = false

    static func enable() {
        guard !enabled else { return }
        enabled = true
        typealias ConnectionID = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let anyImage = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let mainSymbol = dlsym(anyImage, "_CGSDefaultConnection"),
              let setSymbol = dlsym(anyImage, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(mainSymbol, to: ConnectionID.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
